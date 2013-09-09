package AnyEvent::Git::Wrapper;

use strict;
use warnings;
use Carp qw( croak );
use base qw( Git::Wrapper );
use File::pushd;
use AnyEvent;
use AnyEvent::Open3::Simple;
use Git::Wrapper::Exception;
use Git::Wrapper::Statuses;

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

=head2 $git-E<gt>status

=cut

my %STATUS_CONFLICTS = map { $_ => 1 } qw<DD AU UD UA DU AA UU>;

sub status
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
    return $self->SUPER::status(@_);
  }

  my $opt = ref $_[0] eq 'HASH' ? shift : {};
  $opt->{porcelain} = 1;

  $self->RUN('status' => $opt, @_, sub {
    my $out = shift->recv;
    my $stat = Git::Wrapper::Statuses->new;

    for(@$out)
    {
      my ($x, $y, $from, $to) = $_ =~ /\A(.)(.) (.*?)(?: -> (.*))?\z/;
      if ($STATUS_CONFLICTS{"$x$y"})
      {
        $stat->add('conflict', "$x$y", $from, $to);
      }
      elsif ($x eq '?' && $y eq '?')
      {
        $stat->add('unknown', '?', $from, $to);
      }
      else
      {
        $stat->add('changed', $y, $from, $to)
          if $y ne ' ';
        $stat->add('indexed', $x, $from, $to)
          if $x ne ' ';
      }
    }
    
    $cv->send($stat);
  });
  
  $cv;
}

=head2 $git-E<gt>log

=cut

sub log
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
    return $self->SUPER::log(@_);
  }
  
  die "log nonblocking not supported";
}

=head2 $git-E<gt>version

=cut

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
