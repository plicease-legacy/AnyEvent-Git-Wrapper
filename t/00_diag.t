use strict;
use warnings;
use Test::More tests => 1;

BEGIN { eval q{ use EV } }

my @modules = sort qw(
  AnyEvent
  Git::Wrapper
  AnyEvent::Open3::Simple
  EV
  File::pushd
  Scalar::Util
  Sort::Version
  Test::Deep
  Test::Exception
);

pass 'okay';

diag '';
diag '';
diag '';

diag sprintf "%-25s %s", 'perl', $^V;

diag sprintf "%-25s %s", 'git', do {
  my($version) = eval {
    require AnyEvent::Git::Wrapper;
    AnyEvent::Git::Wrapper->new('.')->version;
  };
  defined $version ? $version : '';
};

foreach my $module (@modules)
{
  if(eval qq{ use $module; 1 })
  {
    my $ver = eval qq{ \$$module\::VERSION };
    $ver = 'undef' unless defined $ver;
    diag sprintf "%-25s %s", $module, $ver;
  }
  else
  {
    diag sprintf "%-25s none", $module;
  }
}

diag '';
diag '';
diag '';

