#!/usr/local/ensembl/bin/perl -w

# File name: CreateCoreTestDatabase.pl
#
# Given a source and destination database this script will create 
# a ensembl core database and perform 2Mbases of test data insertion 
#


use strict;

use Getopt::Long;
use DBI;

my ($help, $srcDB, $destDB, $host, $user, $pass, $port, $seq_region_file);

my $ref_genome_db_id = 1;
my @other_genome_db_ids = qw(3 11);
my $method_link_id = 1;

GetOptions('help' => \$help,
           's=s' => \$srcDB,
	   'd=s' => \$destDB,
	   'h=s' => \$host,
	   'u=s' => \$user,
	   'p=s' => \$pass,
	   'port=i' => \$port,
           'seq_region_file=s' => \$seq_region_file);

my $usage = "Usage:
CreateComparaTestDatabase.pl -s srcDB -d destDB -h host -u user -p pass -seq_region_file file [--port port]\n";

if ($help) {
  print $usage;
  exit 0;
}

unless($port) {
  $port = 3306;
}

# If needed command line args are missing print the usage string and quit
$srcDB and $destDB and $host and $user and $pass and $seq_region_file or die $usage;

my @seq_regions = @{do $seq_region_file};

my $dsn = "DBI:mysql:host=$host;port=$port";

# Connect to the mySQL host
my $dbh = DBI->connect( $dsn, $user, $pass, {RaiseError => 1})
  or die "Could not connect to database host : " . DBI->errstr;

print "\nWARNING: If the $destDB database already exists the existing copy \n"
  . "will be destroyed. Proceed (y/n)? ";

my $key = lc(getc());

unless( $key =~ /y/ ) {
  $dbh->disconnect();
  print "Test Genome Creation Aborted\n";
  exit;
}

print "Proceeding with test genome database $destDB creation\n";  

# dropping any destDB database if there
my $array_ref = $dbh->selectall_arrayref("SHOW DATABASES LIKE '$destDB'");
if (scalar @{$array_ref}) {
  $dbh->do("DROP DATABASE $destDB");
}
# creating destination database
$dbh->do( "CREATE DATABASE " . $destDB )
  or die "Could not create database $destDB: " . $dbh->errstr;

# Dump the source database table structure (w/o data) and use it to create
# the new database schema

# May have to eliminate the -p pass part... not sure

my $rc = 0xffff & system(
  "mysqldump -p$pass -u $user -h $host -P $port --no-data $srcDB | " .
  "mysql -p$pass -u $user -h $host -P $port $destDB");

if($rc != 0) {
  $rc >>= 8;
  die "mysqldump and insert failed with return code: $rc";
}
$dbh->do("use $destDB");

#$dbh->do("insert into source select * from $srcDB.source");
$dbh->do("insert into method_link select * from $srcDB.method_link");
# need to do something a bit more clever here to just add what we really
#$dbh->do("insert into method_link_species_set select * from $srcDB.method_link_species_set");

$dbh->do("insert into genome_db select * from $srcDB.genome_db");
$dbh->do("update genome_db set locator=NULL");

$dbh->do("insert into meta select * from $srcDB.meta");
$array_ref = $dbh->selectcol_arrayref("select meta_value from meta where meta_key='max_alignment_length'");
my $max_alignment_length = $array_ref->[0];

foreach my $genome_db_id (@other_genome_db_ids) {
  foreach my $seq_region (@seq_regions) {
    my ($seq_region_name, $seq_region_start, $seq_region_end) = @{$seq_region};
    my $lower_bound = $seq_region_start - $max_alignment_length;
    my ($method_link_species_set_id) = $dbh->selectrow_array(qq{
          SELECT
            mls1.method_link_species_set_id
          FROM
            $srcDB.method_link_species_set mls1, $srcDB.method_link_species_set mls2
          WHERE
            mls1.genome_db_id=$ref_genome_db_id AND
            mls2.genome_db_id=$genome_db_id AND
            mls1.method_link_species_set_id=mls2.method_link_species_set_id AND
            mls1.method_link_id=$method_link_id
        });
    
    # Get dnafrag_id for the reference region
    my ($dnafrag_id) = $dbh->selectrow_array(qq{
          SELECT
            dnafrag_id
          FROM
            $srcDB.dnafrag
          WHERE
            genome_db_id=$ref_genome_db_id AND
            name=$seq_region_name
        });
    print "Dumping data for dnafrag $dnafrag_id (genome=$ref_genome_db_id; seq=$seq_region_name)\n";
            
    # Get the list of genomic_align_block_ids corresponding the the reference region
    # Populate the genomic_align_block_id table
    print " - dumping genomic_align entries\n";

    $dbh->do(qq{
          INSERT IGNORE INTO
            genomic_align
          SELECT
            *
          FROM
            $srcDB.genomic_align
          WHERE
            method_link_species_set_id=$method_link_species_set_id AND
            dnafrag_id = $dnafrag_id AND
            dnafrag_start<=$seq_region_end AND
            dnafrag_end>=$seq_region_start AND
            dnafrag_start>=$lower_bound
        });
       
    # populate genomic_align_block table
    print " - dumping genomic_align_block entries\n";
    $dbh->do(qq{
          INSERT IGNORE INTO
            genomic_align_block
          SELECT
            gab.*
          FROM
            $srcDB.genomic_align_block gab, genomic_align ga
          WHERE
            gab.genomic_align_block_id=ga.genomic_align_block_id
        });
        
    # populate genomic_align table
    print " - dumping new genomic_align entries\n";
    $dbh->do(qq{
          INSERT IGNORE INTO
            genomic_align
          SELECT
            ga.*
          FROM
            genomic_align_block gab, $srcDB.genomic_align ga
          WHERE
            gab.genomic_align_block_id=ga.genomic_align_block_id
        });
        
    # populate genomic_align_group table
    print " - dumping genomic_align_group entries\n";
    $dbh->do(qq{
          INSERT IGNORE INTO
            genomic_align_group
          SELECT
            gag.*
          FROM
            $srcDB.genomic_align_group gag, genomic_align ga
          WHERE
            gag.genomic_align_id=ga.genomic_align_id
        });

    # populate homology table
    print " - populating homology table\n";
#    my $srcDB2 = "ensembl_compara_22_1";
    $dbh->do("insert into homology select h.* from $srcDB.homology h,$srcDB.homology_member hm1, $srcDB.member m1, $srcDB.homology_member hm2, $srcDB.member m2 where h.homology_id=hm1.homology_id and h.homology_id=hm2.homology_id and hm1.member_id=m1.member_id and hm2.member_id=m2.member_id and m1.genome_db_id=$ref_genome_db_id and m2.genome_db_id=$genome_db_id and m1.chr_name=$seq_region_name and m1.chr_start<$seq_region_end and m1.chr_end>$seq_region_start");

    # populate family table
    print " - populating family table\n";
    $dbh->do("insert ignore into family select f.* from $srcDB.family f, $srcDB.family_member fm, $srcDB.member m where f.family_id=fm.family_id and fm.member_id=m.member_id and m.genome_db_id=$ref_genome_db_id and m.chr_name=$seq_region_name and m.chr_start<$seq_region_end and m.chr_end>$seq_region_start");
    
    print " - done\n";
  }
}


# populate dnafrag table
$dbh->do("insert ignore into dnafrag select d.* from genomic_align ga, $srcDB.dnafrag d where ga.dnafrag_id=d.dnafrag_id");

foreach my $genome_db_id (@other_genome_db_ids) {
  # populate synteny_region table
  $dbh->do("insert into synteny_region select s.* from $srcDB.synteny_region s, $srcDB.dnafrag_region dr1, dnafrag d1, $srcDB.dnafrag_region dr2, dnafrag d2 where s.synteny_region_id=dr1.synteny_region_id and s.synteny_region_id=dr2.synteny_region_id and dr1.dnafrag_id=d1.dnafrag_id and dr2.dnafrag_id=d2.dnafrag_id and d1.genome_db_id=$ref_genome_db_id and d2.genome_db_id=$genome_db_id");
}

# populate dnafrag_region tables
$dbh->do("insert into dnafrag_region select dr.* from synteny_region s, $srcDB.dnafrag_region dr where s.synteny_region_id=dr.synteny_region_id");

# populate homology_member table
$dbh->do("insert into homology_member select hm.* from homology h, $srcDB.homology_member hm where h.homology_id=hm.homology_id");

# populate family_member table
$dbh->do("insert into family_member select fm.* from family f, $srcDB.family_member fm where f.family_id=fm.family_id");

# populate member table
$dbh->do("insert ignore into member select m.* from family_member fm, $srcDB.member m where fm.member_id=m.member_id");
$dbh->do("insert ignore into member select m.* from homology_member hm, $srcDB.member m where hm.member_id=m.member_id");
$dbh->do("insert ignore into member select m.* from homology_member hm, $srcDB.member m where hm.peptide_member_id=m.member_id");

# populate sequence table
$dbh->do("insert into sequence select s.* from member m, $srcDB.sequence s where m.sequence_id=s.sequence_id");

# populate taxon table
$dbh->do("insert ignore into taxon select t.* from member m, $srcDB.taxon t where m.taxon_id=t.taxon_id");
$dbh->do("insert ignore into taxon select t.* from genome_db g, $srcDB.taxon t where g.taxon_id=t.taxon_id");

# populate the method_link_species.....not it is needed with the current schema
# it will when moving to the multiple alignment enabled schema.

# need to do something a bit more clever here to just add what we really
# method_link_species_set entries from genomic_align_block
$dbh->do("insert into method_link_species_set select mlss.* from $srcDB.method_link_species_set mlss, genomic_align_block gab where gab.method_link_species_set_id=mlss.method_link_species_set_id group by mlss.method_link_species_set_id, mlss.method_link_id, mlss.genome_db_id");

# method_link_species_set entries from homology
$dbh->do("insert into method_link_species_set select mlss.* from $srcDB.method_link_species_set mlss, homology h where h.method_link_species_set_id=mlss.method_link_species_set_id group by mlss.method_link_species_set_id, mlss.method_link_id, mlss.genome_db_id");

# method_link_species_set entries from family
$dbh->do("insert into method_link_species_set select mlss.* from $srcDB.method_link_species_set mlss, family f where f.method_link_species_set_id=mlss.method_link_species_set_id group by mlss.method_link_species_set_id, mlss.method_link_id, mlss.genome_db_id");

# method_link_species_set entries from synteny_region/dnafrag_region


# Now output the mouse and rat seq_region file needed to create the corresponding core databases
foreach my $genome_db_id (@other_genome_db_ids) {
  my $array_ref = $dbh->selectcol_arrayref("select name from genome_db where genome_db_id=$genome_db_id");
  my $species_name = lc($array_ref->[0]);
  $species_name =~ s/\s+/_/g;
  my $file = $species_name . ".seq_region_file";

  open F, ">$file" or
    die "can not open $file\n";
  print F "[\n";
  
  $array_ref = $dbh->selectall_arrayref("select d.name,g.dnafrag_start,g.dnafrag_end from dnafrag d, genomic_align g where d.dnafrag_id=g.dnafrag_id and d.genome_db_id=$genome_db_id order by d.name, g.dnafrag_start,g.dnafrag_end");

  my ($last_name, $last_start,$last_end);
  foreach my $row (@{$array_ref}) {
    my ($name,$start,$end) = @{$row};
    unless (defined $last_name && defined $last_start && defined $last_end) {
      ($last_name, $last_start,$last_end) = ($name,$start,$end);
      next;
    }
    if ($name eq $last_name && $start - $last_end < 100000) {
      $last_end = $end;
    } elsif (($name eq $last_name && $start - $last_end >= 100000) ||
             $name ne $last_name) {
      print F "[$last_name, $last_start,$last_end],\n";
      ($last_name, $last_start,$last_end) = ($name,$start,$end);
    }
  }
  print F "[$last_name, $last_start,$last_end]\n]\n";

  close F;
}

$dbh->disconnect();

print "Test genome database $destDB created\n";

# cmd to dump .sql and .txt files
# /usr/local/ensembl/mysql/bin/mysqldump -hia64f -uensadmin -pensembl -P3306 --socket=/mysql/data_3306/mysql.sock -T ./ abel_core_test

exit 0;
