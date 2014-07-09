package Bowtie2;

use warnings;
use strict;

# $Id: Bowtie2.pm 55 2013-05-15 11:41:39Z s187512 $

use File::Temp;
use File::Spec;
use File::Which;
use Data::Dumper;

use IPC::Open3;
use IPC::Run qw(harness pump start);

use Log::Log4perl qw(:easy :no_extra_logdie_message);


#-----------------------------------------------------------------------------#
# Globals

our $VERSION = '0.02';

my $L = Log::Log4perl::get_logger();

$|++;



##------------------------------------------------------------------------##

=head1 NAME 

Bowtie2.pm

=head1 DESCRIPTION

Bowtie2 interface.

=head1 SYNOPSIS

  use Bowtie2;
  
  my $bowtie2 = Bowtie2->new(
    path => 'path/to/bowtie2/bin/'   # unless exported
  );
  
  $bowtie2->build("genome.fa");
  
  $bowtie2->run(qw( # bowtie2 parameter
      -x genome.fa
      -1 reads_1.fq
      -2 reads_2.fq
    ),
    { # perl module specific arguments
       ??
    }
  );
  
  # read output on the fly
  use Sam::Parser;
  my $sp = Sam::Parser->new(
    fh => $bowtie2->stdout
  );
  
  while(my $aln = $sp->next_aln()){
    # do something with the output

    # and maybe stop the run midways  
    $bowtie2->cancel 

  }
 
  # wait for the run to finish  
  $bowtie2->finish; 



=cut



##------------------------------------------------------------------------##

=head1 Class ATTRIBUTES

=cut



##------------------------------------------------------------------------##

=head1 Class METHODS

=cut



##------------------------------------------------------------------------##

=head1 Constructor METHOD

=head2 new

  my $bowtie2 = Bowtie2->new(
    path => 'path/to/bowtie2/bin/'   # unless exported
  );

=cut


sub new{

    $L->debug("initiating object");

    my $proto = shift;
    my $self;
    my $class;
    
    # object method -> clone + overwrite
    if($class = ref $proto){ 
	return bless ({%$proto, @_}, $class);
    }

    # class method -> construct + overwrite
    # init empty obj
    $self = {
	path => '',
	bowtie2_bin => 'bowtie2',
	bowtie2_build_bin => 'bowtie2-build',
	@_,
	_stdin => undef,
	_stdout => undef,
	_stderr => undef,
	_status => 'initiated',
	_pid => undef,
    };

    bless $self, $proto;    
    
    $self->check_binaries;

    return $self;

}




sub DESTROY{
	my $self = shift;
}


##------------------------------------------------------------------------##

=head1 Public METHODS

=head2 build

Create a bowtie2 index for a given reference. For convenience, the
index prefix defaults to the basename of the reference genome file.

  $bowtie2->build("Genome.fa", "Genome-index-prefix);

=cut

sub build{
    my $self = shift;
    
    # overwrite global settings
    $self = {%$self , %{pop @_}} if ref $_[-1] eq "HASH";

    # process paramater
    my @p=@_ == 1 ? (@_) x 2 : @_;

    # check status
    $L->logdie("Current status '".$self->status()."'. 'finish' prior to any other new action")
	if $self->status =~ /^running/;

    # let open3 do its magic :)	
    use Symbol 'gensym'; 
    $self->{_stderr} = gensym;
    $self->{_pid} = open3(
	$self->{_stdin},
	$self->{_stdout},
	$self->{_stderr},
	$self->bowtie2_build_bin,
	@p
	);

    $self->{_status} = "running bowtie2->build";
    $L->debug($self->{_status});
    
    # wait for indexing to finish
    waitpid($self->{_pid}, 0);


    # check for return status
    my $e = $self->stderr;
    my $o = $self->stdout;

    if($?){
	my $exitval = $? >> 8;
	$self->{_status} =~ s/running/exited($exitval)/;
	$L->info( <$o> );
	$L->warn( <$e> );
    }else{
	# set status to 
	$self->{_status} =~ s/running/finished/;
	$L->info( <$o> );
	$L->warn( <$e> );
    }

    $L->debug($self->{_status});

    return $self
}

=head2 run

Run bowtie2 as background process.

  $bowtie2->run(qw(-x Genome.fa -1 read_1.fq -2 read_2.fq ...));

=cut

sub run{

    my $self = shift;
    
    # overwrite global settings
    $self = {%$self , %{pop @_}} if ref $_[-1] eq "HASH";

    # process paramater

    # check status
    $L->logdie("Current status '".$self->status()."'. 'finish' prior to any other new action")
	if $self->status =~ /^running/;

    # let open3 do its magic :)	
    use Symbol 'gensym'; 
    $self->{_stderr} = gensym;
    $self->{_pid} = open3(
	$self->{_stdin},
	$self->{_stdout},
	$self->{_stderr},
	$self->bowtie2_bin,
	@_
	);

    $self->{_status} = "running bowtie2->run";
    $L->debug($self->{_status});

	
    # fork timeout process to monitor the run and cancel it, if necessary
    # child
    if(!$self->{out} && $self->{timeout} && !( $self->{_timeout_pid} = fork()) ){
	# fork error
	if ( not defined $self->{_timeout_pid} ){ die "couldn't fork: $!\n"; }
	$self->_timeout(); 
	# childs exits either after timeout canceled blast or blast run has finished
    }
    # parent - simply proceeds
    
    return $self

}


=head2 finish

Public Method. Waits for the finishing/canceling of a 
 started bowtie2 run. Checks for errors, removes tempfiles.

  my $bowtie2->finish;

=cut

sub finish{
    my ($self) = @_; 

    unless (ref $self || ref $self ne "Bowtie2" ){
	die "Bowtie2 not initialized!\n";
    }

 
    # to make sure, bowtie2 is finished, read its STDOUT until eof
    unless($self->{out}){
    	my $tmp;
    	1 while read($self->{_stdout},$tmp,10000000);
    }

    waitpid($self->{_pid}, 0);
    
    # check for return status
    my $e = $self->stderr;
    my $o = $self->stdout;

    if($?){
	my $exitval = $? >> 8;
	$self->{_status} =~ s/running/exited($exitval)/;
	$L->info( <$o> );
	$L->warn( <$e> );
    }else{
	# set status to 
	$self->{_status} =~ s/running/finished/;
	$L->info( <$o> );
	$L->warn( <$e> );
    }

    $L->debug($self->{_status});
    return $self;
}



=head2 cancel

Public Method. Cancels a running bowtie2 run based on a passed query process id 
or the internally stored process id of the bowtie2 object;

  my $bowtie2->cancel(<message>);
  
  Bowtie2->cancel(pid, <message>);

=cut

sub cancel {
	my ($pid, $msg);
	# object method
	if(ref (my $me = shift)){
		$pid = $me ->{_pid};
		$me->{_status} =~ s/^\w+/canceled/;

		$msg = shift;
	}
	# class method
	else{
		($pid, $msg) = @_;
	}
	
	unless( kill ('1', $pid) ){
		# TODO: cancel pid does not exist
#		$pid." doesnt exist -> probably already finished\n");
	};
}


sub check_binaries{
    my ($self) = @_;
    my $bin = $self->path ? $self->bowtie2_bin : which($self->bowtie2_bin);
    $L->logdie('Cannot execute '.$self->bowtie2_bin) unless -e $bin && -x $bin;
    my $bbin = $self->path ? $self->bowtie2_bin : which($self->bowtie2_build_bin);
    $L->logdie('Cannot execute '.$self->bowtie2_build_bin) unless -e $bbin && -x $bbin;

    $L->debug("Using binaries: $bin, $bbin");
}


##------------------------------------------------------------------------##

=head1 Accessor METHODS

=cut

=head2 opt2string

Get a stringified version of the specified parameter for a command.

  $bowtie2_opt = $self->opt2string("bowtie2");
  $bowtie2_build_opt = $self->opt2string("bowtie2_build");
  

=cut

sub opt2string{
	my ($self, $cmd, @more) = @_;
	die("unknown command") unless exists $self->{$cmd.'_opt'};
	return Bowtie2->Param_join($self->{$cmd.'_opt'}, @more) || '';
}

=head2 path

Get/Set the path to the binaries.

=cut

sub path{
	my ($self, $path) = @_;
	$self->{path} = $path if defined($path);
	return $self->{path};
}

=head2 status

Get the current status of the bowtie object.

=cut

sub status{
	my ($self) = @_;
	return $self->{_status};
}

=head2 stderr

Get the filehandle to the stderr stream. Only available while status is 
'running'.

=cut

sub stderr{
	my ($self) = @_;
	return $self->{_stderr};
}

=head2 stdout

Get the filehandle to the stdout stream. Only available prior to C<< $bowtie2->finish >>.

=cut

sub stdout{
	my ($self) = @_;
	return $self->{_stdout};
}

 
sub bowtie2_bin{
	my ($self) = @_;
	return File::Spec->catfile($self->{path} || (), $self->{bowtie2_bin});
}


sub bowtie2_build_bin{
	my ($self) = @_;
	return File::Spec->catfile($self->{path} || (), $self->{bowtie2_build_bin});
}

##------------------------------------------------------------------------##

=head1 Private Methods

=cut

=head2 timeout

Private Method. Initialized by run if C<timeout> > than 0;

=cut

sub _timeout {
	my ($self) = @_; 
	my $time = 0;
	# set sleep to default 2 seconds if not specified
	if(not defined $self->{_sleep} ){ 
		# set sleep time to never be higher than timeout, but maximal 2 seconds
		$self->{_sleep} = $self->{timeout} < 2 ? $self->{timeout} : 2;
	}
	while(my $pid = kill ('0', $self->{ _pid}) ){ 
		if($time > $self->{timeout}){
			$self->cancel( 'Canceled by timeout '.$self->{timeout}."s" );
			exit(0); 
		}else{
			$time += $self->{_sleep};	
			sleep($self->{_sleep});
		}
	}
	exit(0);
}




=head1 AUTHOR

Thomas Hackl S<thomas.hackl@uni-wuerzburg.de>

=cut



1;


