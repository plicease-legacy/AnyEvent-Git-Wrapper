use strict;
use warnings;
use Test::More;

use File::Temp qw(tempdir);
use IO::File;
use AnyEvent;
use AnyEvent::Git::Wrapper;
use File::Spec;
use File::Path qw(mkpath);
use POSIX qw(strftime);
use Sort::Versions;
use Test::Deep;
use Test::Exception;

# FIXME: add a timeout

my $dir = tempdir(CLEANUP => 1);

my $git = AnyEvent::Git::Wrapper->new($dir);

my $version = $git->version;
if ( versioncmp( $git->version , '1.5.0') eq -1 ) {
  plan skip_all =>
    "Git prior to v1.5.0 doesn't support 'config' subcmd which we need for this test."
}

#diag( "Testing git version: " . $version );

$git->init(AE::cv)->recv; # 'git init' also added in v1.5.0 so we're safe

do {
  my $cv = AE::cv;
  
  $cv->begin;
  $git->config( 'user.name'  , 'Test User'        , sub { $cv->end });
  $cv->begin;
  $git->config( 'user.email' , 'test@example.com' , sub { $cv->end });

  # make sure git isn't munging our content so we have consistent hashes
  $cv->begin;
  $git->config( 'core.autocrlf' , 'false' , sub { $cv->end });
  $cv->begin;
  $git->config( 'core.safecrlf' , 'false' , sub { $cv->end });
  
  $cv->recv;
};

mkpath(File::Spec->catfile($dir, 'foo'));

IO::File->new(File::Spec->catfile($dir, qw(foo bar)), '>:raw')->print("hello\n");

$git->ls_files({ o => 1 }, sub {
  my($out, $err) = shift->recv;
  is_deeply( $out, [ 'foo/bar' ] , 'ls_files -o');
})->recv;

$git->add('.', AE::cv)->recv;

$git->ls_files(sub {
  my($out, $err) = shift->recv;
  is_deeply( $out, [ 'foo/bar' ] , 'ls_files -o');
})->recv;

SKIP: {
  skip 'testing old git without porcelain' , 1 unless $git->supports_status_porcelain;

  # TODO: nb version of status
  is( $git->status->is_dirty , 1 , 'repo is dirty' );
}

my $time = time;
$git->commit({ message => "FIRST\n\n\tBODY\n" }, AE::cv)->recv;

SKIP: {
  skip 'testing old git without porcelain' , 1 unless $git->supports_status_porcelain;

  # TODO: nb version of status
  is( $git->status->is_dirty , 0 , 'repo is clean' );
}


my @rev_list;

$git->rev_list({ all => 1, pretty => 'oneline' }, sub {
  my($out, $err) = shift->recv;
  @rev_list= @$out;
  is(@rev_list, 1);
  like($rev_list[0], qr/^[a-f\d]{40} FIRST$/);
})->recv;

# TODO: nb version of log
my $args = $git->supports_log_raw_dates ? { date => 'raw' } : {};
my @log = $git->log( $args );
is(@log, 1, 'one log entry');

my $log = $log[0];
is($log->id, (split /\s/, $rev_list[0])[0], 'id');
is($log->message, "FIRST\n\n\tBODY\n", "message");

SKIP: {
  skip 'testing old git without raw date support' , 1
    unless $git->supports_log_raw_dates;

  my $log_date = $log->date;
  $log_date =~ s/ [+-]\d+$//;
  cmp_ok(( $log_date - $time ), '<=', 5, 'date');
}

SKIP:
{
  skip 'testing old git without no abbrev commit support' , 1
    unless $git->supports_log_no_abbrev_commit;

  $git->config( 'log.abbrevCommit', 'true' , AE::cv)->recv;

  # TODO: nb version of log
  @log = $git->log( $args );

  $log = $log[0];
  is($log->id, (split /\s/, $rev_list[0])[0], 'id');
}

SKIP:
{
  if ( versioncmp( $git->version , '1.6.3') eq -1 ) {
    skip 'testing old git without log --oneline support' , 3;
  }

  # TODO: nb version of log
  throws_ok { $git->log('--oneline') } qr/^unhandled/ , 'log(--oneline) dies';

  $git->RUN('log', '--oneline', sub {
    my($out, $err) = shift->recv;
    my @lines = @$out;
    lives_ok { @lines  } 'RUN(log --oneline) lives';
    is( @lines , 1 , 'one log entry' );
  });
}

# TODO: nb version of log
my @raw_log = $git->log({ raw => 1 });
is(@raw_log, 1, 'one raw log entry');

sub _timeout (&) {
    my ($code) = @_;

    my $timeout = 0;
    eval {
        local $SIG{ALRM} = sub { $timeout = 1; die "TIMEOUT\n" };
        # 5 seconds should be more than enough time to fail properly
        alarm 5;
        $code->();
        alarm 0;
    };

    return $timeout;
}

# TODO: nb-ify the rest of this test

SKIP: {
    if ( versioncmp( $git->version , '1.7.0.5') eq -1 ) {
      skip 'testing old git without commit --allow-empty-message support' , 1;
    }

    # Test empty commit message
    IO::File->new(">" . File::Spec->catfile($dir, qw(second_commit)))->print("second_commit\n");
    $git->add('second_commit');

    # If this fails there's a distinct danger it will hang indefinitely
    my $timeout = _timeout { $git->commit };
    ok !$timeout && $@, 'Attempt to commit interactively fails quickly'
        or diag "Timed out!";

    $timeout = _timeout {
      $git->commit({ message => "", 'allow-empty-message' => 1 });
    };

    if ( $@ && !$timeout ) {
      my $msg = substr($@,0,50);
      skip $msg, 1;
    }

    @log = $git->log();
    is(@log, 2, 'two log entries, one with empty commit message');
};


# test --message vs. -m
my @arg_tests = (
    ['message', 'long_arg_no_spaces',   'long arg, no spaces in val',  ],
    ['message', 'long arg with spaces', 'long arg, spaces in val',     ],
    ['m',       'short_arg_no_spaces',  'short arg, no spaces in val', ],
    ['m',       'short arg w spaces',   'short arg, spaces in val',    ],
);

my $arg_file = IO::File->new('>' . File::Spec->catfile($dir, qw(argument_testfile)));

for my $arg_test (@arg_tests) {
    my ($flag, $msg, $descr) = @$arg_test;

    $arg_file->print("$msg\n");
    $git->add('argument_testfile');
    $git->commit({ $flag => $msg });

    my ($arg_log) = $git->log('-n 1');

    is $arg_log->message, "$msg\n", "argument test: $descr";
}

$git->checkout({b => 'new_branch'});

my ($new_branch) = grep {m/^\*/} $git->branch;
$new_branch =~ s/^\*\s+|\s+$//g;

is $new_branch, 'new_branch', 'new branch name is correct';

SKIP: {
  skip 'testing old git without no-filters' , 1 unless $git->supports_hash_object_filters;

  my ($hash) = $git->hash_object({
    no_filters => 1,
    stdin      => 1,
    -STDIN     => 'content to hash',
  });
  is $hash, '4b06c1f876b16951b37f4d6755010f901100f04e',
    'passing content with -STDIN option';
}

done_testing();