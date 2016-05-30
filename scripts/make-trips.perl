#!/usr/bin/env perl

use strict;
use warnings;

use FindBin;
use lib ( $FindBin::Bin );  # for local modules
use CwcConfig;

use Getopt::Long;

# ------------------------------------------------------------
# Global Variables

# Set to enable verbose (debugging) output.
my $verbose = 0;

# ------------------------------------------------------------
# Parse Arguments

GetOptions('v|verbose'          => \$verbose,
          )
  or die("Error parsing arguments.");

# There should be just one argument, the name of the TRIPS system to
# make.
my $which_trips;
if (1 == scalar(@ARGV)) {
  $which_trips = lc(shift(@ARGV));
}
else {
  die("Need command line arg with TRIPS system to build, \"bob\" or \"cabot\"");
}

if (("bob" eq $which_trips) or
    ("cabot" eq $which_trips)) {
  # Great!
  print("Attempting to make: $which_trips\n");
}
else {
  die("TRIPS system should be: \"bob\" or \"cabot\"");
}

# ------------------------------------------------------------
# Perform any one-time setup.

CwcConfig::load_config(0);

my $repo_name = "trips-$which_trips";
my $repo_ref = CwcConfig::get_repo_config_ref($repo_name);
defined($repo_ref) or
  die("Unable to find repo config for: $repo_name");

my $repo_dir = $repo_ref->{dir};
defined($repo_dir) or
  die ("Repo config (for $repo_name) did not include dir.");

my $src_dir = "$repo_dir/src";
(-d $src_dir) or
  die ("Repo src directory ($src_dir) did not exist. Try running verify-env.perl.");

# Do the rest of the work in the src directory.
chdir($src_dir);

# ------------------------------------------------------------
# Main script

# First, check if configured.
my $configured = 0;
if (-e "$src_dir/Makefile") {
  # We have a Makefile, assume it was created by a call to configure
  # (and isn't there via magic or something).
  $configured = 1;
}

if (not $configured) {
  print("Need to configure TRIPS manually before building.\n");
  print("See the documentation in:\n");
  print("  $repo_dir/Docs/building-trips.html\n");
  print("You may be able to configure TRIPS with a command like:\n");
  print("  cd $src_dir\n");
  print("  ./configure --with-lisp=sbcl --with-fasl=fasl --with-lisp-flavor=sbcl --with-corenlp=\$PWD/../../nl/stanford-corenlp-full-2014-06-16/ --with-geonames=\$PWD/../../geonames/2015-12-01/NationalFile_20151201.zip --with-wordnet=\$PWD/../../nl/WordNet-3.0/dict/ --with-mesh-scr=\$PWD/../../nl/mesh/c2015.bin.gz\n");
  
  exit(1);
}

# FIXME We are configured, go looking to see if we are up to date.


# End of main script
# ------------------------------------------------------------
# Subroutines
