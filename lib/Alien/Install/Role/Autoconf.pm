package Alien::Install::Role::Autoconf;

use strict;
use warnings;
use Role::Tiny;
use Alien::Install::Util;
use Carp qw( carp );

# ABSTRACT: Installer role for Autoconf
# VERSION

requires 'extract';
requires 'chdir_source';
requires 'test_compile_run';
requires 'test_ffi';
requires 'build_install_cflags';
requires 'build_install_libs';
requires 'build_install_dlls';

register_build_requires 'Alien::MSYS' => '0.07'
  if $^O eq 'MSWin32';

sub _msys
{
  my($sub) = @_;
  if($^O eq 'MSWin32')
  {
    require Alien::MSYS;
    return Alien::MSYS::msys(sub{ $sub->('make') });
  }
  require Config;
  $sub->($Config::Config{make});
}

sub configure_arguments { ('--with-pic') };

sub build_install
{
  my($class, $prefix, %options) = @_;
  
  $options{test} ||= 'compile';
  die "test must be one of compile, ffi or both"
    unless $options{test} =~ /^(compile|ffi|both)$/;
  die "need an install prefix" unless $prefix;
  
  $prefix =~ s{\\}{/}g;
  
  my $dir = $options{dir} || do { require File::Temp; File::Temp::tempdir( CLEANUP => 1 ) };
  
  carp "use archive instead of tar"
    if exists $options{tar};
  $class->extract($options{archive} || $options{tar} || $class->fetch, $dir);
  
  require Cwd;
  my $save = Cwd::getcwd();
  
  chdir $dir;  
  my $build = eval {
  
    $class->chdir_source($dir);
  
    $class->call_hooks('pre_build', $dir, $prefix);
  
    _msys(sub {
      my($make) = @_;
      system 'sh', 'configure', "--prefix=$prefix", $class->configure_arguments;
      die "configure failed" if $?;
      system $make, 'all';
      die "make all failed" if $?;
      $class->call_hooks('post_build', $dir, $prefix);
      system $make, 'install';
      die "make install failed" if $?;
    });

    $class->call_hooks('post_install', $prefix);
    
    my $build = bless {
      cflags  => $class->build_install_cflags($prefix),
      libs    => $class->build_install_libs($prefix),
      prefix  => $prefix,
      dll_dir => [ 'dll' ],
      dlls    => $class->build_install_dlls(catdir($prefix, 'dll')),
    }, $class;

    $class->call_hooks('post_instantiate');
    
    $build->test_compile_run || die $build->error if $options{test} =~ /^(compile|both)$/;
    $build->test_ffi         || die $build->error if $options{test} =~ /^(ffi|both)$/;
    
    $class->call_hooks('post_test');
    
    $build;
  };
  
  my $error = $@;
  chdir $save;
  die $error if $error;
  $build;
}

1;