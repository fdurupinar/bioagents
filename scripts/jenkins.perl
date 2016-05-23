#!/usr/bin/env perl
#
# This script performs the steps of a Jenkins build. It returns 0 if
# the build is successful, or a non-zero value if there was a problem.
#
# While this is intended to run in Jenkins, it can (and should) also
# be run locally by developers who want to make sure their changes are
# unlikely to break the build.
#
# * NOTE on LISP-UTILS
#
# The SIFT Jenkins instance is configured to poll multiple SCMs
# for changes. When it detects changes, it performs a build. There are
# a bunch of Lisp libraries (in the lisp-utils directory) that are not
# configured in Jenkins. This script retrieves the latest versions of
# those libraries by calling verify-env.perl with the "fix"
# argument. Thus, changes to the lisp-utils will not trigger builds,
# but will be tested with the next update to one of the core projects.
#
# 

use strict;
use warnings;

use FindBin;
use Getopt::Long;
use POSIX;
use Time::HiRes;

# ------------------------------------------------------------
# Global Variables

# Set to enable verbose (debugging) output.
my $verbose = 0;

# Maximum time for the script to run before we give up.
my $timeout_s = 3600;

# If set, build TRIPS if necessary. Otherwise, assume that the current
# TRIPS build is acceptable.
my $build = 0;

# ------------------------------------------------------------
# Parse Arguments

GetOptions('v|verbose'          => \$verbose,
           't|timeout=i'    => \$timeout_s,
           'b|build'            => \$build,
          )
  or die("Error parsing arguments.");

# ------------------------------------------------------------
# Timeout
#
# Fork a child to form its own process group. The parent will sit
# around for a specified timeout. If the timeout is reached, it
# signals the child and we exit.

if(0 != $timeout_s) {
  print("Setting timeout for $timeout_s s.\n");
}

my $child = fork();
if(0 < $child) {
  # I'm the parent. Set a SIGCHILD handler so that our sleep can be
  # interrupted. Sleep for a while, then have the child shutdown.
  $SIG{CHLD} = sub{
    my $pid = wait();
    # print("Child ($pid) exited.\n");
    if($child == $pid) {
      my $exit_code = $?;
      # Shift to the right by 8 to get the exit code.
      $exit_code = $exit_code >> 8;
      # print("Child exit code was: $exit_code\n");
      exit($exit_code);
    }
  };

  # Pass signals through to child.
  $SIG{TERM} = $SIG{INT} = $SIG{QUIT} = $SIG{HUP} = $SIG{ABRT} = sub {
    my $sig = shift;
    print("got SIG$sig, passing on to child ($child)\n");
    kill($sig, $child);
  };

  if(0 != $timeout_s) {
    sleep($timeout_s);
    print("Done sleeping, time to die.\n");
    kill('USR1', $child);
  }

  # We sleep indefinitely, because the SIGCHLD handler will exit.
  print("Waiting for child ($child).\n");
  while(1) {
    sleep(1);
  }

  die("I don't know what happened, I don't think we should have gotten here...\n");
}
elsif(0 > $child) {
  die("Error forking child for timeout.");
}

# I'm the child. Setup a signal handler and proceed with doing all
# the work...
my $process_group = POSIX::setsid();
print("I ($$) am the child, and have become process group: $process_group\n");

# This will be set to 1 if we time out.
my $timed_out = 0;
$SIG{USR1} = sub {
  print("------------------------------------------------------------\n");
  # print("Timed out after $timeout_s seconds.\n");
  print("I (the child process) was given SIGUSR1.\n");
  print("Sending TERM to process group: $process_group\n");
  $SIG{TERM} = 'IGNORE';
  # This assumes that all children will die gracefully in response to SIGTERM,
  # but zombie children may still persist if signal is ignored.
  kill(-15, $process_group);
  # exit(1);
  $timed_out = 1;
  exit(1);
};

# This will be set to the signal name if we are killed. Not sure we
# actually need it though.
my $killed = "";
$SIG{'TERM'} = $SIG{'INT'} = $SIG{'QUIT'} = $SIG{'HUP'} = $SIG{'ABRT'} = sub {
  my $sig = shift;
  print("got SIG$sig, Sending TERM to process group ($process_group)\n");
  $SIG{'TERM'} = 'IGNORE';
  kill(-15, $process_group);
  $killed = $sig;
  exit(1);
};

# ------------------------------------------------------------
# Main script

my $script_start_time = Time::HiRes::time();

# ------------------------------------------------------------
# Verify that we have a sane environment.

my $verify_start_time = Time::HiRes::time();

my @verify_cmd =
  (
   $FindBin::Bin . "/verify-env.perl",
   "--fix",
  );
if ($verbose) {
  push(@verify_cmd, "--verbose");
  print("Verifying env with command:\n");
  print("  " . join(" ", @verify_cmd) . "\n");
}
my $env_result = exec_child(\@verify_cmd);
if (0 != $env_result) {
  exit($env_result);
}

my $verify_end_time = Time::HiRes::time();

# ------------------------------------------------------------
# Check to see if a TRIPS build is needed. Build if necessary.

# FIXME Implement this.
# my $build_start_time = Time::HiRes::time();
# my $build_end_time = Time::HiRes::time();

# ------------------------------------------------------------
# Run the tests we know about.

my $tests_start_time = Time::HiRes::time();

my @test_systems =
  (
   ":spire",
   ":spire/test-sparser",
  );

my %test_result_refs = ();
foreach my $system (@test_systems) {
  my $test_start_time = Time::HiRes::time();
  my @test_cmd =
    (
     $FindBin::Bin . "/run-test.perl",
     $system,
    );
  if ($verbose) {
    push(@test_cmd, "--verbose");
  }
  my $test_result = exec_child(\@test_cmd);
  my $test_end_time = Time::HiRes::time();

  my $result_ref = ();
  $result_ref->{result} = $test_result;
  my $test_duration_s = $test_end_time - $test_start_time;
  $result_ref->{duration_s} = $test_duration_s;
  $test_result_refs{$system} = $result_ref;
}

my $tests_end_time = Time::HiRes::time();
my $script_end_time = Time::HiRes::time();

# ------------------------------------------------------------
# Print a summary of the results.

print("------------------------------------------------------------\n");
print("Test Results:\n");
my $pass = 1;
foreach my $system (@test_systems) {
  printf("  %-25s ... ", $system);
  my $result_ref = $test_result_refs{$system};
  my $result = $result_ref->{result};
  if (0 == $result) {
    # Success.
    print("SUCCESS");
  }
  else {
    # Failure.
    print("FAILURE");
    $pass = 0;
  }
  my $test_duration_s = $result_ref->{duration_s};
  printf(" -- %0.1f s\n", $test_duration_s);
}

print("------------------------------------------------------------\n");
my $verify_duration_s = $verify_end_time - $verify_start_time;
printf("Verify took:   %0.1f s\n", $verify_duration_s);
# my $build_duration_s = $build_end_time - $build_start_time;
# printf("Build took:    %0.1f s\n", $build_duration_s);
my $tests_duration_s = $tests_end_time - $tests_start_time;
printf("Tests took:    %0.1f s\n", $tests_duration_s);
my $script_duration_s = $script_end_time - $script_start_time;
printf("Total time:    %0.1f s\n", $script_duration_s);
print("------------------------------------------------------------\n");

if ($pass) {
  print("Build SUCCEEDED\n");
  exit(0);
}
else {
  print("Build FAILED\n");
  exit(1);
}

# End of main script.
#------------------------------------------------------------
# Subroutines

sub exec_child {
  my $cmd_ref = shift();

  $verbose and
    print("Running command: " . join(" ", @$cmd_ref) . "\n");

  my $child = fork();
  if (0 < $child) {
    # We're the parent, wait for the chld.
    waitpid($child, 0);
    # Then, get the exit code.
    my $result = $?;
    my $exit_code = ($result >> 8);
    return $exit_code;
  }
  elsif (0 > $child) {
    die("fork() failed.");
  }
  else {
    # We're the child... become the command we wanna be.
    exec(@$cmd_ref);
    die("Shouldn't have gotten here.");
  }
};

