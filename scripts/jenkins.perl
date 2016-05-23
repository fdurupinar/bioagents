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

# ------------------------------------------------------------
# Global Variables

# Set to enable verbose (debugging) output.
my $verbose = 0;

# If set, build TRIPS if necessary. Otherwise, assume that the current
# TRIPS build is acceptable.
my $build = 0;

# ------------------------------------------------------------
# Parse Arguments

GetOptions('v|verbose'          => \$verbose,
           'b|build'            => \$build,
          )
  or die("Error parsing arguments.");

# ------------------------------------------------------------
# Verify that we have a sane environment.

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
my $env_result = system(@verify_cmd);
if (0 != $env_result) {
  exit($env_result);
}

# ------------------------------------------------------------
# Check to see if a TRIPS build is needed. Build if necessary.

# FIXME Implement this.

# ------------------------------------------------------------
# Run the tests we know about.

my @test_systems =
  (
   ":spire",
   ":spire/test-sparser",
  );

my %test_results = ();
foreach my $system (@test_systems) {
  my @test_cmd =
    (
     $FindBin::Bin . "/run-test.perl",
     $system,
    );
  if ($verbose) {
    push(@test_cmd, "--verbose");
    print("Running test with command:\n");
    print("  " . join(" ", @test_cmd) . "\n");
  }
  my $test_result = system(@test_cmd);
  $test_results{$system} = $test_result;
}

# ------------------------------------------------------------
# Print a summary of the results.

print("Results:\n");
my $pass = 1;
foreach my $system (@test_systems) {
  printf("  %-20s ... ", $system);
  my $result = $test_results{$system};
  if (0 == $result) {
    # Success.
    print("SUCCESS\n");
  }
  else {
    # Failure.
    print("FAILURE\n");
    $pass = 0;
  }
}

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

