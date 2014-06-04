use strict;
use warnings;
use Test::More;
use File::Temp qw( tempdir );
use File::Spec;

BEGIN {
  plan skip_all => "set ALIEN_LIBARCHIVE_INSTALLER_EXTRA_TESTS to run test"
    unless $ENV{TRAVIS_JOB_ID} || $ENV{ALIEN_LIBARCHIVE_INSTALLER_EXTRA_TESTS};
  plan skip_all => "test requires HTTP::Tiny"
    unless eval q{ use HTTP::Tiny; 1 };
  plan skip_all => "test requires AnyEvent::Open3::Simple"
    unless eval q{ use AE; use AnyEvent::Open3::Simple; 1 };
}

BEGIN {   
  *CORE::GLOBAL::system = sub {
    my $done = AE::cv;
    my $ipc = AnyEvent::Open3::Simple->new(
      on_stdout => sub {
        my($proc,$line) = @_;
        note("stdout: $line");
      },
      on_stderr => sub {
        my($proc,$line) = @_;
        note "stderr: $line";
      },
      on_exit => sub {
        my($proc,$exit,$sig) = @_;
        $done->send($exit << 8 | $sig);
      },
      on_error => sub {
        $done->send(-1);
      },
    );
    note "% @_";
    $ipc->run(@_);
    $? = $done->recv;
  };
}

use Alien::Libarchive::Installer;

plan tests => 3;

my $prefix = tempdir( CLEANUP => 1 );

my $installer = Alien::Libarchive::Installer->new;

foreach my $version (qw( 3.1.2 3.0.4 2.8.4 ))
{
  subtest "build version $version" => sub {
    plan tests => 5;
    my $tar = $installer->fetch( version => $version );
    my $build = eval { $installer->build_install( File::Spec->catdir($prefix, $version), tar => $tar ) };
    is $@, '', 'no error';
    SKIP: {
      is $build->{version}, $version,    "version = $version";
      ok $build->{extra_linker_flags},   "extra_linker_flags = ".   join(' ', @{ $build->{extra_linker_flags}   });
      ok $build->{extra_compiler_flags}, "extra_compiler_flags = ". join(' ', @{ $build->{extra_compiler_flags} });
      my $exe = File::Spec->catfile($prefix, $version, 'bin', 'bsdtar' . ($^O =~ /^(MSWin32|cygwin)$/ ? '.exe' : ''));
      ok -r $exe, "created executable $exe";
    };
  };
}
