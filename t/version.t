use strict;
use warnings;
use Test::More tests => 2;
use AnyEvent::Git::Wrapper;
use File::Temp qw( tempdir );

my $git = AnyEvent::Git::Wrapper->new(tempdir CLEANUP => 1);

my $version = $git->version(AE::cv)->recv;
ok defined($version) && $version, "nb version = $version";

is $git->version, $version, "nb and blocking version matches";
