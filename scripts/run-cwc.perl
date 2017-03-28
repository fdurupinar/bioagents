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
use CwcRun;
use Timeout;

use Cwd;
use Getopt::Long;
use IO::Handle;
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

# If set runs TRIPS with -nouser flag.
my $nouser = 0;

# If set, opens a web browser to the demo page.
my $start_browser = 0;

# Default to the bio domain.
my $domain = "bio";

# If set, use the raw-executive mockup instead of the full
# TRIPS-enabled system.
my $rem = 0;

my $source_config_filename =
  $FindBin::Bin . "/../cwc-source-config.lisp";

# ------------------------------------------------------------
# Parse arguments

GetOptions('v|verbose'          => \$verbose,
           't|timeout=i'        => \$timeout_s,
           'n|nouser'           => \$nouser,
           's|show-browser'     => \$start_browser,
           'r|rem|raw-exec-mockup' => \$rem,
          )
  or die("Error parsing arguments.");

if (0 < scalar(@ARGV)) {
  $domain = shift(@ARGV);
  if (0 < scalar(@ARGV)) {
    warn("Can only handle a single domain argument, ignoring: " . join(" ", @ARGV));
  }
}

my $script_start_time = Time::HiRes::time();

# Values of what to run. These are set based on the $domain and used
# below.
my $which_trips;
my $run_bioagents;
my $system_name;
my $url;
my @system_startup_commands = ( "(start-spg)" );
my $system_prefix = "SPG";

if ($domain =~ /^(?:bio|biocuration)$/i) {
  print("Running BIO domain.\n");
  if ($rem) {
    die("SORRY! BIO domain currently cannot be run without TRIPS. Do not use the -r|-raw-exec-mockup argument.");
  }
  $which_trips = "bob";
  $run_bioagents = 1;
  $system_name = ":spg/bio";
  $url = "http://localhost:8000/bio";
}
elsif ($domain =~ /^(?:bw|blocksworld)$/i) {
  print("Running BLOCKSWORLD domain.\n");
  if ($rem) {
    $which_trips = undef;
    $system_name = ":clic/bw";
    @system_startup_commands =
      ( "(clic:register-bw-rem-handlers)",
        "(clic:init-clic-web-blocksworld)"
      );
    $system_prefix = "CLIC";
  }
  else {
    $which_trips = "cabot";
    $system_name = ":spg/bw";
  }
  $run_bioagents = 0;
  $url = "http://localhost:8000/bw";
}
else {
  die ("Do not understand domain: $domain");
}

# ------------------------------------------------------------
# Timeout

Timeout::fork_timeout_process($timeout_s);

# ------------------------------------------------------------
# TRIPS

my $trips;
if (defined($which_trips)) {
  $trips = CwcRun::start_trips($which_trips, $nouser);
}

# ------------------------------------------------------------
# Bioagents

my $bioagents;
my $tfta;
if ($run_bioagents) {
  ($bioagents, $tfta) = CwcRun::start_bioagents();
}

# ------------------------------------------------------------
# Run the LISP process for CLIC.

$verbose and
  print("Running CLIC system: $system_name\n");
my @clic_cmd =
  (
   "sbcl",
   "--dynamic-space-size", 4096,
   "--non-interactive",
   # "--disable-debugger",
   "--no-sysinit",
   "--no-userinit",
   "--load", $source_config_filename,
   "--eval", "(asdf:load-system $system_name)",
  );

foreach my $startup_command (@system_startup_commands) {
  push(@clic_cmd, "--eval", $startup_command);
}

push(@clic_cmd,
     # Print a message to identify readiness.
     "--eval", "(format t \"CLIC is READY~%\")",
     # Sleep essentially forever -- 1 year! Forcing output every second.
     "--eval", "(dotimes (n 31536000) (finish-output *standard-output*) (sleep 1))",
    );
my $clic = CwcRun::ipc_run(Cwd::abs_path($FindBin::Bin . "/.."),
                           \@clic_cmd,
                           $system_prefix,
                           \&handle_clic_events);

# ------------------------------------------------------------
# Process output from the subprocesses as long as there is some.

my $print_time = Time::HiRes::time();
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
  if (defined($tfta)) {
    if ($tfta->pumpable()) {
      $tfta->pump_nb();
    }
    else {
      # This should *not* have exited.
      die("TFTA exited unexpectedly.");
    }
  }

  # Try to pump CLIC.
  if ($clic->pumpable()) {
    $clic->pump_nb();
  }
  else {
    # Whoa. CLIC exited.
    print("CLIC finished, getting exit code.\n");
    $clic->finish();
    $done = 1;
  }

  my $cur_time = Time::HiRes::time();
  my $since_last_print_s = $cur_time - $print_time;
  if (1.0 < $since_last_print_s) {
    print(".");
    $CwcRun::need_newline = 1;
    $print_time = $cur_time;
  }
  STDOUT->flush();

  CwcRun::avoid_polling_open_loop();
}

exit(0);

# End of Main Script
# ------------------------------------------------------------
# Subroutines

# Check to see if an output should trigger anything.
sub handle_clic_events {
  my $in = shift();

  if ($in =~ /CLIC is READY/) {
    print("CLIC is ready.\n");

    my $ready_time = Time::HiRes::time();
    my $ready_duration_s = $ready_time - $script_start_time;
    printf("Startup took %0.1fs.\n", $ready_duration_s);

    if ($start_browser) {
      print("Opening web browser to:\n");
      print("  $url\n");
      system("open $url &");
    }
    else {
      print("Open a browser to:\n");
      print("  $url\n");
    }
  }
}
