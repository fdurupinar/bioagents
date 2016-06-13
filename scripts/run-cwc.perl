#!/usr/bin/env perl
#
# Runs the full integrated CwC system.
#
# Run as:
# ./run-cwc.perl bw
# ./run-cwc.perl bio
#
# If no argument is provided, assumes bio domain.
#
# FIXME Move the shared portions of this script and run-test.perl to a
# library to eliminate duplication.
#
# This script began life as a copy of the run-test.perl script. The
# only difference was in argument handling and in the specific command
# eval'd by SBCL.
#

use strict;
use warnings;

use FindBin;
use lib ( $FindBin::Bin );  # for local modules
use CwcConfig;
use Timeout;

use Cwd;
use Getopt::Long;
use IPC::Run;

# Autoflush stdout.
$| = 1;

# ------------------------------------------------------------
# Global variables

# Set to enable verbose (debugging) output.
my $verbose = 0;

# How long to run before timing out and exiting.
my $timeout_s = 0;

# If set runs TRIPS with -nouser flag.
my $nouser = 0;

# If set, opens a web browser to the demo page.
my $start_browser = 0;

# Default to the bio domain.
my $domain = "bio";

my $source_config_filename =
  $FindBin::Bin . "/../cwc-source-config.lisp";

# ------------------------------------------------------------
# Parse arguments

GetOptions('v|verbose'          => \$verbose,
           't|timeout=i'        => \$timeout_s,
           'nouser'             => \$nouser,
           's|show-browser'     => \$start_browser,
          )
  or die("Error parsing arguments.");

if (0 < scalar(@ARGV)) {
  $domain = shift(@ARGV);
  if (0 < scalar(@ARGV)) {
    warn("Can only handle a single domain argument, ignoring: " . join(" ", @ARGV));
  }
}

# Values of what to run. These are set based on the $domain and used
# below.
my $which_trips;
my $run_bioagents;
my $system_name;
my $url;

if ($domain =~ /bio|biocuration/i) {
  print("Running BIO domain.\n");
  $which_trips = "bob";
  $run_bioagents = 1;
  $system_name = ":spg/bio";
  if ($start_browser) {
    $url = "http://localhost:8000/bio";
  }
}
elsif ($domain =~ /bw|blocksworld/i) {
  print("Running BLOCKSWORLD domain.\n");
  $which_trips = "cabot";
  $run_bioagents = 0;
  $system_name = ":spg/bw";
  if ($start_browser) {
    $url = "http://localhost:8000/bw";
  }
}
else {
  die ("Do not understand domain: $domain");
}

# Load the config so that we can properly find everything.
CwcConfig::load_config(0);

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

  my @trips_cmd = ( $trips_exe );
  if ($nouser) {
    push(@trips_cmd, '-nouser');
  }
  $trips = ipc_run($trips_bin_dir,
                   \@trips_cmd,
                   "TRIPS");

  print("Sleeping a few seconds to let TRIPS get started.\n");
  sleep(6);
}

# ------------------------------------------------------------
# Bioagents

my $bioagents;
if ($run_bioagents) {
  $bioagents = ipc_run(Cwd::abs_path($FindBin::Bin . "/.."),
                       [$FindBin::Bin . "/run-bioagents.perl"]);
  print("Sleeping a few seconds to let bioagents get started.\n");
  sleep(6);
}

# ------------------------------------------------------------
# Run the LISP process for SPG.

$verbose and
  print("Running SPG system: $system_name\n");
my $spg = ipc_run(Cwd::abs_path($FindBin::Bin . "/.."),
                  [ "sbcl",
                    "--non-interactive",
                    "--no-sysinit",
                    "--no-userinit",
                    "--load", $source_config_filename,
                    "--eval", "(asdf:load-system $system_name)",
                    "--eval", "(start-spg)",
                    # Print a message to identify readiness.
                    "--eval", "(format t \"SPG is READY~%\")",
                    # Sleep essentially forever -- 1 year!
                    "--eval", "(sleep 31536000)",
                  ],
                  "SPG");

# ------------------------------------------------------------
# Process output from the subprocesses as long as there is some.

my $done = 0;
while (not $done) {
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

  # Try to pump SPG.
  if ($spg->pumpable()) {
    $spg->pump_nb();
  }
  else {
    # Whoa. The SPG exited.
    print("SPG finished, getting exit code.\n");
    $spg->finish();
    $done = 1;
  }
}

exit(0);

# End of Main Script
# ------------------------------------------------------------
# Subroutines

sub ipc_run {
  my $working_dir = shift();
  my $cmd_ref = shift();
  my $prefix = shift();

  # Move to the desired working dir.
  my $orig_dir = Cwd::abs_path(".");
  chdir($working_dir);

  print("Running IPC command:\n");
  print("  " . join(" ", @$cmd_ref) . "\n");
  my $ipc = IPC::Run::start($cmd_ref,
                            '>pty>',
                            IPC::Run::new_chunker,
                            sub {
                              my $in = shift();
                              if (defined($prefix)) {
                                print("$prefix: ");
                              }
                              print($in);
                            });

  # Go back to the orig dir.
  chdir($orig_dir);

  return $ipc;
}

