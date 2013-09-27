use strict;
use warnings;
use AnyEvent::Git::Wrapper;
use Test::More;

our $format;
diag sprintf $format, 'git', AnyEvent::Git::Wrapper->new(".")->version;

1;
