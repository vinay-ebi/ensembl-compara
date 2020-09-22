=head1 LICENSE

Copyright [1999-2015] Wellcome Trust Sanger Institute and the EMBL-European Bioinformatics Institute
Copyright [2016-2020] EMBL-European Bioinformatics Institute

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

     http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.

=head1 NAME

Bio::EnsEMBL::Compara::RunnableDB::HomologyAnnotation::DiamondBlastp

=head1 DESCRIPTION

Create fasta file containing batch_size number of sequences. Run DIAMOND and parse the output into
PeptideAlignFeature objects. Store PeptideAlignFeature objects in the compara database

=cut

package Bio::EnsEMBL::Compara::RunnableDB::HomologyAnnotation::DiamondBlastp;

use strict;
use warnings;

use base ('Bio::EnsEMBL::Compara::RunnableDB::BlastAndParsePAF');

sub get_queries {
    my $self = shift @_;

    my $start_member_id = $self->param_required('start_member_id');
    my $end_member_id   = $self->param_required('end_member_id');

    #Get list of members and sequences
    my $member_ids = $self->compara_dba->get_HMMAnnotAdaptor->fetch_all_seqs_missing_annot_by_range($start_member_id, $end_member_id, 'no_null');
    return $self->compara_dba->get_SeqMemberAdaptor->fetch_all_by_dbID_list($member_ids);
}

sub run {
    my $self = shift @_;

    #my $diamond_exe             = $self->param('diamond_exe'); 
    # This will be in ENV.pm once installed properly in farm, currently diamond is installed locally in my $USER .bin/
    my $diamond_exe             = 'diamond';
    my $blast_params            = $self->param('blast_params')  || '';  # no parameters to C++ binary means having composition stats on and -seg masking off
    my $evalue_limit            = $self->param('evalue_limit');
    my $tophits                 = $self->param('tophits');

    my $worker_temp_directory   = $self->worker_temp_directory;

    my $blast_infile  = $worker_temp_directory . '/blast.in.'.$$;     # only for debugging
    my $blast_outfile = $worker_temp_directory . '/blast.out.'.$$;    # looks like inevitable evil (tried many hairy alternatives and failed)

    Bio::EnsEMBL::Compara::Utils::Preloader::load_all_sequences($self->compara_dba->get_SequenceAdaptor, undef, $self->param('query_set'));

    if ($self->debug) {
        print "diamond_infile $blast_infile\n";
        my $members = $self->param('query_set')->get_all_Members;
        foreach my $member ( @$members ) {
            print Dumper $member unless $member->isa('Bio::EnsEMBL::Compara::SeqMember');
        }
        $self->param('query_set')->print_sequences_to_file($blast_infile, -format => 'fasta');
    }

    $self->compara_dba->dbc->disconnect_if_idle();

    my $cross_pafs = [];
    foreach my $blast_db (keys %{$self->param('all_blast_db')}) {
        my $target_genome_db_id = $self->param('all_blast_db')->{$blast_db};

        my $cmd = "$diamond_exe blastp -d $blast_db --evalue $evalue_limit --out $blast_outfile --outfmt 6 qseqid sseqid evalue score nident pident qstart qend sstart send length positive ppos qseq_gapped sseq_gapped $blast_params";

        my $run_cmd = $self->write_to_command($cmd, sub {
                my $blast_fh = shift;
                $self->param('query_set')->print_sequences_to_file($blast_fh, -format => 'fasta');
        } );
        print "Time for diamond search " . $run_cmd->runtime_msec . " msec\n";

        my $features = $self->parse_blast_table_into_paf($blast_outfile, $self->param('genome_db_id'), $target_genome_db_id);

        unless($self->param('expected_members') == scalar(keys(%{$self->param('num_query_member')}))) {
            # Most likely, this is happening due to MEMLIMIT, so make the job sleep if it parsed 0 sequences, to wait for MEMLIMIT to happen properly.
            sleep(5);
        }

        push @$cross_pafs, @$features;
        unlink $blast_outfile unless $self->debug;
    }

    $self->param('cross_pafs', $cross_pafs);
}
1;