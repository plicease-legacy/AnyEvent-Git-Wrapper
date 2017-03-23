# AnyEvent::Git::Wrapper [![Build Status](https://secure.travis-ci.org/plicease/AnyEvent-Git-Wrapper.png)](http://travis-ci.org/plicease/AnyEvent-Git-Wrapper)

Wrap git command-line interface without blocking

# SYNOPSIS

    use AnyEvent::Git::Wrapper;
    
    # add all files and make a commit...
    my $git = AnyEvent::Git::Wrapper->new($dir);
    $git->add('.', sub {
      $git->commit({ message => 'initial commit' }, sub {
        say "made initial commit";
      });
    });

# DESCRIPTION

**DEPRECATED**: May go away at some point.

This module provides a non-blocking and blocking API for git in the style and using the data 
structures of [Git::Wrapper](https://metacpan.org/pod/Git::Wrapper).  For methods that execute the git binary, if the last argument is 
either a code reference or an [AnyEvent](https://metacpan.org/pod/AnyEvent) condition variable, then the command is run in 
non-blocking mode and the result will be sent to the condition variable when the command completes.  
For most commands (all those but `status`, `log` and `version`), the result comes back via the 
`recv` method on the condition variable as two array references, one representing the standard out 
and the other being the standard error.  Because `recv` will return just the first value if 
called in scalar context, you can retrieve just the output by calling `recv` in scalar context.

    # ignoring stderr
    $git->branch(sub {
      my $out = shift->recv;
      foreach my $line (@$out)
      {
        ...
      }
    });
    
    # same thing, but saving stderr
    $git->branch(sub {
      my($out, $err) = shit->recv;
      foreach my $line(@$out)
      {
        ...
      }
    });

Like [Git::Wrapper](https://metacpan.org/pod/Git::Wrapper), you can also access the standard output and error via the `OUT` and `ERR`, but care
needs to be taken that you either save the values immediately if other commands are being run at the same
time.

    $git->branch(sub {
      my $out = $git->OUT;
      foreach my $line (@$out)
      {
        ...
      }
    });

If git signals an error condition the condition variable will croak, so you will need to wrap your call
to `recv` in an eval if you want to handle it:

    $git->branch(sub {
      my $out = eval { shift->recv };
      if($@)
      {
        warn "error: $@";
        return;
      }
      ...
    });

# CONSTRUCTOR

## new

    my $git = AnyEvent::Git::Wrapper->new('.');

The constructor takes all the same arguments as [Git::Wrapper](https://metacpan.org/pod/Git::Wrapper), in addition to 
these options:

- cache\_version

    The first time the `version` command is executed the value will be cached so
    that `git version` doesn't need to be executed again (via the `version` method
    only, this doesn't include if you call `git version` using the `RUN` method).
    The default is false (no cache).

# METHODS

## RUN

Run the given git command with the given arguments (see [Git::Wrapper](https://metacpan.org/pod/Git::Wrapper)).  If the last argument is
either a code reference or a condition variable then the command will be run in non-blocking mode
and a condition variable will be returned immediately.  Otherwise the command will be run in 
normal blocking mode, exactly like [Git::Wrapper](https://metacpan.org/pod/Git::Wrapper).

If you provide this method with a condition variable it will use that to send the results of the
command.  If you provide a code reference it will create its own condition variable and attach
the code reference  to its callback.  Either way it will return the condition variable.

    # blocking
    $git->RUN($command, @arguments);
    
    # non-blocking callback
    $git->RUN($command, @arguments, sub {
      # $out is a list ref of stdout
      # $err is a list ref of stderr
      my($out, $err) = shift->recv;
    });
    
    # non-blocking cv
    my $cv = $git->RUN($command, @arguments, AE::cv);
    $cv->cb(sub {
      my($out, $err) = shift->recv;
    });

## status

If called in blocking mode (without a code reference or condition variable as the last argument),
this method works exactly as with [Git::Wrapper](https://metacpan.org/pod/Git::Wrapper).  If run in non blocking mode, the [Git::Wrapper::Statuses](https://metacpan.org/pod/Git::Wrapper::Statuses)
object will be passed back via the `recv` method on the condition variable.

    # blocking
    # $statuses isa Git::Wrapper::Statuses
    my $statuses = $git->status;

    # with a code ref
    $git->status(sub {
      # $statuses isa Git::Wrapper::Statuses 
      my $statuses = shift->recv;
      ...
    });
    
    # with a condition variable
    my $cv = $git->status(AE::cv)
    $cv->cb(sub {
      # $statuses isa Git::Wrapper::Statuses
      my $statuses = shift->recv;
      ...   
    });

## log

This method has three different calling modes, blocking, non-blocking as commits arrive and non-blocking
processed at completion.

- blocking mode

        $git->log(@args);

    Works exactly like [Git::Wrapper](https://metacpan.org/pod/Git::Wrapper)

- as commits arrive

        # without a condition variable
        $git->log(@args, sub {
          # $commit isa Git::Wrapper::Log
          my $commit;
          ...
        }, sub {
          # called when complete
          ...
        });
        
        # with a condition variable
        my $cv = AnyEvent->condvar;
        $git->log(@args, sub {
          # $commit isa Git::Wrapper::Log
          my $commit;
          ...
         }, $cv); 
         $cv->cb(
           # called when complete
           ...
         });

    With this calling convention the first callback is called for each commit,as it arrives from git.
    The second callback, or condition variable is fired after the command has completed and all commits
    have been processed.

- at completion

        # with a callback
        $git->log(@args, sub {
          # @log isa array of Git::Wrapper::Log
          my @log = shift->recv;
        });
        
        # with a condition variable
        my $cv = AnyEvent->condvar;
        $git->log(@args, $cv);
        $cv->cb(
          # @log isa array of Git::Wrapper::Log
          my @log = shift->recv;
        });

    With this calling convention the commits are processed by `AnyEvent::Git::Wrapper` as they come
    in but they are gathered up and returned to the callback or condition variable at completion.

In either non-blocking mode the condition variable for the completion of the command is returned,
so you can pass in `AE::cv` (or `AnyEvent-`condvar>) as the last argument and retrieve it like
this:

    my $cv = $git->log(@args, AE::cv);

## version

In blocking mode works just like [Git::Wrapper](https://metacpan.org/pod/Git::Wrapper).  With a code reference or condition variable it runs in
blocking mode and the version is returned via the condition variable.

    # blocking
    my $version = $git->version;

    # cod ref
    $git->version(sub {
      my $version = shift->recv;
      ...
    });
    
    # cond var
    my $cv = $git->version(AE::cv);
    $cv->cb(sub {
      my $version = shift->recv;
      ...
    });

# CAVEATS

[AnyEvent](https://metacpan.org/pod/AnyEvent) (a dependency of this module) is no longer supported on Perl 5.22
or later by its author.  It may work there, or it may not.

This module necessarily uses the private \_parse\_args method from [Git::Wrapper](https://metacpan.org/pod/Git::Wrapper), so changes
to that module may break this one.  Also, some functionality is duplicated because there
isn't a good way to hook into just parts of the commands that this module overrides.  The
author has made a good faith attempt to reduce the amount of duplication.

You probably don't want to be doing multiple git write operations at once (strange things are
likely to happen), but you may want to do multiple git read operations or mix git and other
[AnyEvent](https://metacpan.org/pod/AnyEvent) operations at once.

# BUNDLED FILES

In addition to inheriting from [Git::Wrapper](https://metacpan.org/pod/Git::Wrapper), this distribution includes tests that come
with [Git::Wrapper](https://metacpan.org/pod/Git::Wrapper), and are covered by this copyright:

This software is copyright (c) 2008 by Hand Dieter Pearcey.

This is free software you can redistribute it and/or modify it under the same terms as the Perl 5
programming language system itself.

Thanks also to Chris Prather and John SJ Anderson for their work on [Git::Wrapper](https://metacpan.org/pod/Git::Wrapper).

# AUTHOR

Graham Ollis <plicease@cpan.org>

# COPYRIGHT AND LICENSE

This software is copyright (c) 2013 by Graham Ollis.

This is free software; you can redistribute it and/or modify it under
the same terms as the Perl 5 programming language system itself.
