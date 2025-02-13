#!/usr/bin/env perl
# See the NOTICE file distributed with this work for additional information
# regarding copyright ownership.
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

use strict;
use warnings;

use Bio::EnsEMBL::Registry;
use Bio::EnsEMBL::Compara::Utils::Registry;

my $curr_release = $ENV{'CURR_ENSEMBL_RELEASE'} || $ENV{'ENS_VERSION'};
my $curr_eg_release = $curr_release - 53;

# Core databases:
Bio::EnsEMBL::Registry->load_registry_from_url("mysql://ensro\@mysql-ens-sta-3-b:4686/$curr_release");

# Protist collections:
my @collection_groups = (
    'alveolata1',
    'amoebozoa1',
    'apusozoa1',
    'choanoflagellida1',
    'cryptophyta1',
    'euglenozoa1',
    'fornicata1',
    'heterolobosea1',
    'ichthyosporea1',
    'nucleariidaeandfonticulagroup1',
    'parabasalia1',
    'rhizaria1',
    'stramenopiles1',
);

foreach my $group ( @collection_groups ) {
    Bio::EnsEMBL::Compara::Utils::Registry::load_collection_core_database(
        -host   => 'mysql-ens-sta-3-b',
        -port   => 4686,
        -user   => 'ensro',
        -pass   => '',
        -dbname => "protists_${group}_collection_core_${curr_eg_release}_${curr_release}_1",
    );
}

# Compara databases:
Bio::EnsEMBL::Compara::Utils::Registry::add_compara_dbas({
    'compara_curr'   => [ 'mysql-ens-compara-prod-8', "ensembl_compara_protists_${curr_eg_release}_${curr_release}" ],
});

# Other databases:
Bio::EnsEMBL::Compara::Utils::Registry::add_taxonomy_dbas({
    'ncbi_taxonomy' => [ 'mysql-ens-sta-3-b', "ncbi_taxonomy_${curr_release}" ],
});


1;
