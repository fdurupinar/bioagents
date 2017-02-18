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
use CwcConfig;
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
my $verbose = 0;

# How long to run before timing out and exiting.
my $timeout_s = 0;

# If set, runs the appropriate TRIPS executive. Should be set to
# either "cabot" or "bob".
my $which_trips;

# Set to 1 when TRIPS has started and the facilitator is listening.
my $trips_ready = 0;

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

# Load the config so that we can properly find everything.
CwcConfig::load_config(0);

# Record the time the script takes.
my $script_start_time = Time::HiRes::time();

# ------------------------------------------------------------
# Timeout

Timeout::fork_timeout_process($timeout_s);

# ------------------------------------------------------------
# TRIPS

my $trips;
if (defined($which_trips)) {
  my $trips_repo_name = "trips-$which_trips";
  my $trips_repo_ref =  CwcConfig::get_git_repo_config_ref($trips_repo_name);
  defined($trips_repo_ref) or
    die("Unable to get repo configuration: $trips_repo_name");
  my $trips_dir = $trips_repo_ref->{dir};
  defined($trips_dir) or
    die("Did not find TRIPS directory in config: $trips_repo_name");
  my $trips_bin_dir = "$trips_dir/bin";
  (-d $trips_bin_dir) or
    die("TRIPS bin directory ($trips_bin_dir) doesn't exist.");
  my $trips_exe = "$trips_bin_dir/trips-$which_trips";

  $trips = CwcRun::ipc_run(Cwd::abs_path('.'),
                           [$trips_exe, '-nouser'],
                           "TRIPS",
                           \&handle_trips_events);

  # Pump trips until TRIPS is ready.
  while (not $trips_ready) {
    if ($trips->pumpable()) {
      $trips->pump_nb();
    }
    else {
      # This should *not* have exited.
      die("TRIPS didn't even get started.");
    }
    sleep(0.1);
  }

  # print("Sleeping a few seconds to let TRIPS get started.\n");
  # sleep(20);
}

# ------------------------------------------------------------
# Bioagents

my $bioagents;
if ($run_bioagents) {
  $bioagents = CwcRun::ipc_run(Cwd::abs_path($FindBin::Bin . "/.."),
                               [$FindBin::Bin . "/run-bioagents.perl"]);
  print("Sleeping a few seconds to let bioagents get started.\n");
  sleep(5);
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
                             "--eval", "(asdf:test-system $test_name)",
                           ],
                           "CLIC");

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
}

print("Test finished with exit code: $test_exit_code\n");

# Get the end time.
my $script_end_time = Time::HiRes::time();
my $script_duration_s = $script_end_time - $script_start_time;
printf("Tests took %0.1fs to run.\n", $script_duration_s);

exit($test_exit_code);

# End of Main Script
# ------------------------------------------------------------
# Subroutines

# Set a flag once TRIPS is ready.
sub handle_trips_events {
  my $in = shift();

  # CABOT and BOB report startup differently.
  if (($in =~ /facilitator: listening on port 6200/) or
      ($in =~ /comm: initialize-socket: localhost:6200/)) {
    print("TRIPS is ready.\n");
    $trips_ready = 1;
  }
}
