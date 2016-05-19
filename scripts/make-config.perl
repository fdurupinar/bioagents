#!/usr/bin/env perl

use strict;
use warnings;

use FindBin;
use lib ( $FindBin::Bin );  # for local modules
use CwcConfig;

use Getopt::Long;
use Path::Class;

# ------------------------------------------------------------
# Constant values

# Base location of cwc-integ stuff.
my $base_dir = dir($FindBin::Bin, "..")->absolute();

# ------------------------------------------------------------
# Global Variables

# Set to enable verbose (debugging) output.
my $verbose = 0;

# ------------------------------------------------------------
# Parse Arguments

GetOptions('v|verbose'          => \$verbose,
          )
  or die("Error parsing arguments.");

# ------------------------------------------------------------
# Perform any one-time setup.

# By default, do everything from the cwc-integ root dir.
chdir($base_dir);
$verbose and
  print("Running in: " . dir(".")->absolute . "\n");

CwcConfig::load_config(1);

# ------------------------------------------------------------
# FIXME Make a config!

exit(0);

# End of main script
# ------------------------------------------------------------
# Subroutines
