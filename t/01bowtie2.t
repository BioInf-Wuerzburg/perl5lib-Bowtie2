#!/usr/bin/env perl

use strict;
use warnings;

use Test::More;
use Test::Deep;
use Data::Dumper;

use FindBin qw($RealBin);
use lib "$RealBin/../lib/";

use Log::Log4perl qw(:easy :levels);
Log::Log4perl->init(\q(
        log4perl.rootLogger                               = DEBUG, Screen
        log4perl.appender.Screen                          = Log::Log4perl::Appender::Screen
        log4perl.appender.Screen.stderr                   = 1
        log4perl.appender.Screen.layout                   = PatternLayout
        log4perl.appender.Screen.layout.ConversionPattern = [%d{MM-dd HH:mm:ss}] [%C] %m%n
));


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
(my $pre = $FindBin::RealScript) =~ s/.t$//; # data structure dumped

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

$t = 'bowtie2-build';
subtest $t => sub{
    unlink glob $pre.'_ref.fa.*.bt2'; # remove old indices
    $o->build($pre.'_ref.fa');
    ok(-e $pre.'_ref.fa.1.bt2', "building index");
};

$t = 'bowtie2';
subtest $t => sub{
    unlink glob $pre.'_ref.sam'; # remove old files
    $o->run(
	-x => $pre.'_ref.fa',
	-1 => $pre.'_reads.fq.gz',
	-2 => $pre.'_reads.fq.gz',
	-S => $pre.'.sam',
	)->finish();
    ok(-e $pre.'.sam', "mapping paired to file");

    $o->run(
	-x => $pre.'_ref.fa',
	-U => $pre.'_reads.fq.gz',
	);

    my $so = $o->stdout;
    is(scalar <$so>, '@HD	VN:1.0	SO:unsorted'."\n", "mapping single, reading on-the-fly and cancel");

    $o->cancel;
    $o->finish;

};



















done_testing();
