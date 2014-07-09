#!/usr/bin/env perl

use strict;
use warnings;

use Test::More;
use Test::Deep;
use Data::Dumper;

use FindBin qw($RealBin);
use lib "$RealBin/../lib/";


#--------------------------------------------------------------------------#
=head2 load module

=cut

BEGIN { use_ok('Bowtie2'); }

my $Class = 'Bowtie2';

#--------------------------------------------------------------------------#
=head2 sample data

=cut


# create data file names from name of this <file>.t
(my $Dat_file = $FindBin::RealScript) =~ s/t$/dat/; # data
(my $Dmp_file = $FindBin::RealScript) =~ s/t$/dmp/; # data structure dumped
(my $Tmp_file = $FindBin::RealScript) =~ s/t$/tmp/; # data structure dumped

my ($Dat, %Dat, %Dmp);

if(-e $Dat_file){
	# slurp <file>.dat
	$Dat = do { local $/; local @ARGV = $Dat_file; <> }; # slurp data to string
	# %Dat = split("??", $Dat);
}

if(-e $Dmp_file){
    # eval <file>.dump
    %Dmp = do "$Dmp_file"; # read and eval the dumped structure
}


#--------------------------------------------------------------------------#
=head1 ClassMethods

=cut


#--------------------------------------------------------------------------#
=head2 new

=cut

my $o;
my $t = 'new object';
subtest $t => sub{
    $o = new_ok($Class);
    cmp_deeply($o, $Dmp{$t}, $t);
    my $o2 = $o->new;
    cmp_deeply($o2, $o, 'new clone');
};





















done_testing();
