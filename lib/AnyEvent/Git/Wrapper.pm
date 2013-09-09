package AnyEvent::Git::Wrapper;

use strict;
use warnings;
use Carp qw( croak );
use base qw( Git::Wrapper );
use File::pushd;
use AnyEvent;
use AnyEvent::Open3::Simple;
use Git::Wrapper::Exception;

# ABSTRACT: Wrap git command-line interface without blocking
# VERSION

=head1 METHODS

=head2 $git-E<gt>RUN($command, [ @arguments ])

=cut

sub RUN
{
  my($self) = shift;
  my $cv;
  if(ref($_[-1]) eq 'CODE')
  {
    $cv = AE::cv;
    $cv->cb(pop);
  }
  elsif(eval { $_[-1]->isa('AnyEvent::CondVar') })
  {
    $cv = pop;
  }
  else
  {
    return $self->SUPER::RUN(@_);
  }

  my $cmd = shift;

  my $in;  
  my @out;
  my @err;
  
  my $ipc = AnyEvent::Open3::Simple->new(
    on_start  => sub {
      my($proc) = @_;
      $proc->print($in) if defined $in;
      $proc->close;
    },
    on_stdout => \@out,
    on_stderr => \@err,
    on_error  => sub {
      my($error) = @_;
      $cv->croak(
        Git::Wrapper::Exception->new(
          output => \@out,
          error  => \@err,
          status => -1,
        )
      );
    },
    on_exit   => sub {
      my($proc, $exit, $signal) = @_;
      
      # borrowed from superclass, see comment there
      my $stupid_status = $cmd eq 'status' && @out && ! @err;
      
      if(($exit || $signal) && ! $stupid_status)
      {
        $cv->croak(
          Git::Wrapper::Exception->new(
            output => \@out,
            error  => \@err,
            status => $exit,
          )
        );
      }
      else
      {
        $self->{err} = \@err;
        $self->{out} = \@out;
        $cv->send(\@out, \@err);
      }
    },
  );
  
  do {
    my $d = pushd $self->dir unless $cmd eq 'clone';
    
    my $parts;
    ($parts, $in) = Git::Wrapper::_parse_args( $cmd, @_ );
    my @cmd = ( $self->git, @$parts );
    
    local $ENV{GIT_EDITOR} = '';
    $ipc->run(@cmd);
  };
  
  $cv;
}

# sub log
# sub status

sub version
{
  my($self) = @_;
  my $cv;
  if(ref($_[-1]) eq 'CODE')
  {
    $cv = AE::cv;
    $cv->cb(pop);
  }
  elsif(eval { $_[-1]->isa('AnyEvent::CondVar') })
  {
    $cv = pop;
  }
  else
  {
    return $self->SUPER::version(@_);
  }
  
  $self->RUN('version', sub {
    my $out = eval { shift->recv };
    if($@)
    {
      $cv->croak($@);
    }
    else
    {
      my $version = $out->[0];
      $version =~ s/^git version //;
      $cv->send($version);
    }
  });
  
  $cv;
}

1;
