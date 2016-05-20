#!/usr/bin/env perl
#
# Runs a single ASDF test with SBCL.
#
# Run as:
# ./run-test.perl :spire
# ./run-test.perl :spire/test-sparser

use strict;
use warnings;

use FindBin;
use Getopt::Long;

# ------------------------------------------------------------
# Global variables

# Set to enable verbose (debugging) output.
my $verbose = 0;

my $source_config_filename =
  $FindBin::Bin . "/../cwc-source-config.lisp";

# ------------------------------------------------------------
# Parse arguments

GetOptions('v|verbose'          => \$verbose,
          )
  or die("Error parsing arguments.");

# ------------------------------------------------------------
# Do the actual testing.

(1 == scalar(@ARGV)) or
  die("Script requires exactly one test name.");

my $test_name = shift(@ARGV);

my @cmd =
  ( "sbcl",
    "--non-interactive",
    "--no-sysinit",
    "--no-userinit",
    "--load", $source_config_filename,
    # Pick one:
    # "--eval", "(asdf:test-system :spire)",
    # "--eval", "(asdf:test-system :spire/test-sparser)",
    "--eval", "(asdf:test-system $test_name)",
  );

$verbose and
  print("Running test: $test_name\n");
$verbose and
  print("Command is:\n");
$verbose and
  print(join(" ", @cmd) . "\n");

# Become the test command.
exec(@cmd);

