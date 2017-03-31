#!/usr/bin/env perl
#
# Runs a single ASDF test with SBCL.
#
# Run as:
# ./run-test.perl :spire
# ./run-test.perl :spire/test-sparser
#
# Can also run TRIPS and/or bioagents to support integrated testing. As in:
# ./run-test.perl --trips cabot :spg/bw-tests
# ./run-test.perl --trips bob --bioagents :spg/bio-tests
#

use strict;
use warnings;

use FindBin;
use lib ( $FindBin::Bin );  # for local modules
use CwcRun;
use Timeout;

use Cwd;
use Getopt::Long;
use IPC::Run;
use Time::HiRes;

# Autoflush stdout.
$| = 1;

# ------------------------------------------------------------
# Global variables

# Set to enable verbose (debugging) output.
our $verbose = 0;

# How long to run before timing out and exiting.
my $timeout_s = 0;

# If set, runs the appropriate TRIPS executive. Should be set to
# either "cabot" or "bob".
my $which_trips;

# If set, runs the bioagents.
my $run_bioagents = 0;

my $source_config_filename =
  $FindBin::Bin . "/../cwc-source-config.lisp";

# ------------------------------------------------------------
# Parse arguments

GetOptions('v|verbose'          => \$verbose,
           't|timeout=i'        => \$timeout_s,
           'trips=s'            => \$which_trips,
           'bioagents'          => \$run_bioagents,
          )
  or die("Error parsing arguments.");

(1 == scalar(@ARGV)) or
  die("Script requires exactly one test name.");
my $test_name = shift(@ARGV);

# Record the time the script takes.
my $script_start_time = Time::HiRes::time();
# This value will be overridden by an output handler. We just set it
# here so that if something goes wrong we don't have an undefined
# variable.
my $system_ready_time = $script_start_time;

# ------------------------------------------------------------
# Timeout

Timeout::fork_timeout_process($timeout_s);

# ------------------------------------------------------------
# TRIPS

my $trips;
if (defined($which_trips)) {
  $trips = CwcRun::start_trips($which_trips, 1);
}

# ------------------------------------------------------------
# Bioagents

my $bioagents;
my $tfta;
if ($run_bioagents) {
  ($bioagents, $tfta) = CwcRun::start_bioagents();
}

# ------------------------------------------------------------
# Run the LISP test process.
$verbose and
  print("Running test: $test_name\n");
my $lisp = CwcRun::ipc_run(Cwd::abs_path($FindBin::Bin . "/.."),
                           [ "sbcl",
                             "--dynamic-space-size", 4096,
                             "--non-interactive",
                             "--no-sysinit",
                             "--no-userinit",
                             "--load", $source_config_filename,
                             "--eval", "(asdf:load-system $test_name)",
                             "--eval", "(format t \"CLIC is READY~%\")",
                             "--eval", "(asdf:test-system $test_name)",
                           ],
                           "CLIC",
                           \&handle_clic_events);

# ------------------------------------------------------------
# Process output from the subprocesses as long as there is some.

my $test_exit_code;
while (not defined($test_exit_code)) {
  # Try to pump TRIPS.
  if (defined($trips)) {
    if ($trips->pumpable()) {
      $trips->pump_nb();
    }
    else {
      # This should *not* have exited.
      die("TRIPS exited unexpectedly.");
    }
  }

  # Try to pump Bioagents.
  if (defined($bioagents)) {
    if ($bioagents->pumpable()) {
      $bioagents->pump_nb();
    }
    else {
      # This should *not* have exited.
      die("Bioagents exited unexpectedly.");
    }
  }
  if (defined($tfta)) {
    if ($tfta->pumpable()) {
      $tfta->pump_nb();
    }
    else {
      # This should *not* have exited.
      die("TFTA exited unexpectedly.");
    }
  }

  # Try to pump LISP.
  if ($lisp->pumpable()) {
    $lisp->pump_nb();
  }
  else {
    # Whoa. I think the child's done!
    print("Test finished, getting exit code.\n");
    $lisp->finish();
    $test_exit_code = $lisp->result(0);
  }
  STDOUT->flush();

  CwcRun::avoid_polling_open_loop();
}

print("Test finished with exit code: $test_exit_code\n");

# Get the end time.
my $system_ready_duration_s = $system_ready_time - $script_start_time;
printf("System was ready in:   %0.1fs\n", $system_ready_duration_s);

my $script_end_time = Time::HiRes::time();
my $tests_duration_s = $script_end_time - $system_ready_time;
printf("Tests ran in:          %0.1fs\n", $tests_duration_s);

my $script_duration_s = $script_end_time - $script_start_time;
printf("Total execution time:  %0.1fs\n", $script_duration_s);

if ($test_exit_code) {
  print("Tests FAILED\n");
}
else {
  print("Tests SUCCEEDED\n");
}

exit($test_exit_code);

# End of Main Script
# ------------------------------------------------------------
# Subroutines

sub handle_clic_events {
  my $in = shift();

  if ($in =~ /CLIC is READY/) {
    $system_ready_time = Time::HiRes::time();
  }
}

