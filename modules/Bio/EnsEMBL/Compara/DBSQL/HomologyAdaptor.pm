package Bio::EnsEMBL::Compara::DBSQL::HomologyAdaptor;

use strict;
use Bio::EnsEMBL::Compara::Homology;
use Bio::EnsEMBL::Compara::DBSQL::BaseRelationAdaptor;

our @ISA = qw(Bio::EnsEMBL::Compara::DBSQL::BaseRelationAdaptor);                 

=head2 fetch_by_Member

 Arg [1]    : Bio::EnsEMBL::Compara::Member $member
 Example    : $homologies = $HomologyAdaptor->fetch_by_Member($member);
 Description: fetch the homology relationships where the given member is implicated
 Returntype : an array reference of Bio::EnsEMBL::Compara::Homology objects
 Exceptions : none
 Caller     : general

=cut

sub fetch_by_Member {
  my ($self, $member) = @_;

  my $join = [[['homology_member', 'hm'], 'h.homology_id = hm.homology_id']];
  my $constraint = "hm.member_id = " .$member->dbID;;

  # This internal variable is used by add_Member_Attribute method 
  # in Bio::EnsEMBL::Compara::BaseRelation to make sure that the first element
  # of the member array is the one that has been used by the user to fetch the
  # homology object
  $self->{'_this_one_first'} = $member->stable_id;

  return $self->generic_fetch($constraint, $join);
}


=head2 fetch_by_Member_paired_species

  Arg [1]    : Bio::EnsEMBL::Compara::Member $member
  Arg [2]    : string $species
               e.g. "Mus_musculus" or "Mus musculus"
  Example    : $homologies = $HomologyAdaptor->fetch_by_Member($member, "Mus_musculus");
  Description: fetch the homology relationships where the given member is implicated
               in pair with another member from the paired species. Member species and
               paired species should be different.
  Returntype : an array reference of Bio::EnsEMBL::Compara::Homology objects
  Exceptions : none
  Caller     : 

=cut

sub fetch_by_Member_paired_species {
  my ($self, $member, $species) = @_;

  $species =~ tr/_/ /;

  my $join = [[['homology_member', 'hm'], 'h.homology_id = hm.homology_id']];
  my $constraint = "hm.member_id = " .$member->dbID;

  my $sth =  $self->generic_fetch_sth($constraint, $join);
  
  my ($homology_id, $stable_id, $description, $source_id, $source_name, $dn, $ds);

  $sth->bind_columns(\$homology_id, \$stable_id, \$description,
                     \$dn ,\$ds, \$source_id, \$source_name);

  my @homology_ids = ();
  
  while ($sth->fetch()) {
    push @homology_ids, $homology_id; 
  }

  return [] unless (scalar @homology_ids);
  
  $join = [[['homology_member', 'hm'], 'h.homology_id = hm.homology_id'],
           [['member', 'm'], 'hm.member_id = m.member_id'],
           [['genome_db', 'gdb'], 'm.genome_db_id = gdb.genome_db_id']];

  my $comma_joined_homology_ids = join(',',@homology_ids);
  $constraint = "gdb.name = '$species' AND hm.homology_id in ($comma_joined_homology_ids)";
  
  # See in fetch_by_Member what is this internal variable for
  $self->{'_this_one_first'} = $member->stable_id;

  return $self->generic_fetch($constraint, $join);
}

sub fetch_by_Member_Homology_source {
  my ($self, $member, $source_name) = @_;

  unless ($member->isa('Bio::EnsEMBL::Compara::Member')) {
    $self->throw("The argument must be a Bio::EnsEMBL::Compara::Member object, not $member");
  }

  $self->throw("source_name arg is required\n")
    unless ($source_name);
  
  my $join = [[['homology_member', 'hm'], 'h.homology_id = hm.homology_id']];
  my $constraint = "s.source_name = $source_name";
  $constraint .= " AND hm.member_id = " . $member->dbID;

  # See in fetch_by_Member what is this internal variable for
  $self->{'_this_one_first'} = $member->stable_id;

  return $self->generic_fetch($constraint, $join);
}

#
# internal methods
#
###################

# internal methods used in multiple calls above to build homology objects from table data  

sub _tables {
  my $self = shift;

  return (['homology', 'h'], ['source', 's']);
}

sub _columns {
  my $self = shift;

  return qw (h.homology_id
             h.stable_id
             h.description
             h.dn
             h.ds
             s.source_id
             s.source_name);
}

sub _objs_from_sth {
  my ($self, $sth) = @_;
  
  my ($homology_id, $stable_id, $description, $dn, $ds, $source_id, $source_name);

  $sth->bind_columns(\$homology_id, \$stable_id, \$description, \$dn, \$ds,
                     \$source_id, \$source_name);

  my @homologies = ();
  
  while ($sth->fetch()) {
    push @homologies, Bio::EnsEMBL::Compara::Homology->new_fast
      ({'_dbID' => $homology_id,
       '_stable_id' => $stable_id,
       '_description' => $description,
       '_dn' => $dn,
       '_ds' => $ds,
       '_source_id' => $source_id,
       '_source_name' => $source_name,
       '_adaptor' => $self});
  }
  
  return \@homologies;  
}

sub _default_where_clause {
  my $self = shift;

  return 'h.source_id = s.source_id';
}

#
# STORE METHODS
#
################

=head2 store

 Arg [1]    : Bio::EnsEMBL::Compara::Homology $homology
 Example    : $HomologyAdaptor->store($homology)
 Description: Stores a homology object into a compara database
 Returntype : int 
              been the database homology identifier, if homology stored correctly
 Exceptions : when isa if Arg [1] is not Bio::EnsEMBL::Compara::Homology
 Caller     : general

=cut

sub store {
  my ($self,$hom) = @_;

  $hom->isa('Bio::EnsEMBL::Compara::Homology') ||
    $self->throw("You have to store a Bio::EnsEMBL::Compara::Homology object, not a $hom");

  my $sql = "SELECT homology_id from homology where stable_id = ?";
  my $sth = $self->prepare($sql);
  $sth->execute($hom->stable_id);
  my $rowhash = $sth->fetchrow_hashref;

  $hom->source_id($self->store_source($hom->source_name));

  if ($rowhash->{homology_id}) {
    $hom->dbID($rowhash->{homology_id});
  } else {
  
    $sql = "INSERT INTO homology (stable_id, source_id, description) VALUES (?,?,?)";
    $sth = $self->prepare($sql);
    $sth->execute($hom->stable_id,$hom->source_id,$hom->description);
    $hom->dbID($sth->{'mysql_insertid'});
  }

  foreach my $member_attribute (@{$hom->get_all_Member_Attribute}) {   
    $self->store_relation($member_attribute, $hom);
  }

  return $hom->dbID;
}

1;
