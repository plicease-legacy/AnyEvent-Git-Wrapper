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
use Git::Wrapper::Log;

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
  
  my $opt = ref $_[0] eq 'HASH' ? shift : {};
  $opt->{no_color}         = 1;
  $opt->{pretty}           = 'medium';
  $opt->{no_abbrev_commit} = 1
    if $self->supports_log_no_abbrev_commit;
  
  my $raw = defined $opt->{raw} && $opt->{raw};
  
  $self->RUN(log => $opt, @_, sub {
    my $out = shift->recv;
    
    my @logs;
    while(my $line = shift @$out) {
      unless($line =~ /^commit (\S+)/)
      {
        $cv->croak("unhandled: $line");
        return;
      }
      
      my $current = Git::Wrapper::Log->new($1);
      
      $line = shift @$out;  # next line
      
      while($line =~ /^(\S+):\s+(.+)$/)
      {
        $current->attr->{lc $1} = $2;
        $line = shift @$out; # next line
      }
      
      if($line)
      {
        $cv->croak("no blank line separating head from message");
        return;
      }
      
      my($initial_indent) = $out->[0] =~ /^(\s*)/ if @$out;
      
      my $message = '';
      while(@$out and $out->[0] !~ /^commit (\S+)/ and length($line = shift @$out))
      {
        $line =~ s/^$initial_indent//; # strip just the indenting added by git
        $message .= "$line\n";
      }
      
      $current->message($message);
      
      if($raw)
      {
        my @modifications;
        while(@$out and $out->[0] =~ m/^\:(\d{6}) (\d{6}) (\w{7})\.\.\. (\w{7})\.\.\. (\w{1})\t(.*)$/)
        {
          push @modifications, Git::Wrapper::File::RawModification->new($6,$5,$1,$2,$3,$4);
          shift @$out;
        }
        $current->modifications(@modifications) if @modifications;
      }
      
      push @logs, $current;
    }
    
    $cv->send(@logs);
  });
  
  $cv;
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
