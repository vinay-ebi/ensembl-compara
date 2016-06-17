#!/usr/bin/env perl
# Copyright [1999-2016] Wellcome Trust Sanger Institute and the EMBL-European Bioinformatics Institute
# 
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
# 
#      http://www.apache.org/licenses/LICENSE-2.0
# 
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.


## Delete 1 tree in the database

use strict;
use warnings;

use Getopt::Long;

use Bio::EnsEMBL::Compara::DBSQL::DBAdaptor;
use Bio::EnsEMBL::Utils::SqlHelper;

my $compara_url;
my $tree_id;

# Use -url mysql://anonymous@mysql-eg-publicsql.ebi.ac.uk:4157/ensembl_compara_fungi_15_68 to access EnsemblGenomes
GetOptions(
    'url=s'         => \$compara_url,
    'tree_id=i'     => \$tree_id,
);


my $dba = new Bio::EnsEMBL::Compara::DBSQL::DBAdaptor(-url => $compara_url);
my $gene_tree_adaptor = $dba->get_GeneTreeAdaptor;
my $helper = Bio::EnsEMBL::Utils::SqlHelper->new(-DB_CONNECTION => $dba->dbc);

my $tree = $gene_tree_adaptor->fetch_by_dbID($tree_id);

$tree->preload();
$helper->transaction(-CALLBACK => sub {
    $gene_tree_adaptor->delete_tree($tree);
});
$tree->release_tree();

