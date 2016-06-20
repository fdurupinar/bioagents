#!/usr/bin/env perl

use strict;
use warnings;

use FindBin;
use lib ( $FindBin::Bin );  # for local modules
use CwcConfig;

use File::Find;
use File::stat;
use Getopt::Long;

# ------------------------------------------------------------
# Global Variables

# Set to enable verbose (debugging) output.
my $verbose = 0;

my $fix = 0;

# ------------------------------------------------------------
# Parse Arguments

GetOptions('v|verbose'          => \$verbose,
           'f|fix'              => \$fix,
          )
  or die("Error parsing arguments.");

# There should be just one argument, the name of the TRIPS system to
# make.
my $repo_name;
if (1 == scalar(@ARGV)) {
  $repo_name = lc(shift(@ARGV));
}
else {
  die("Need command line arg with TRIPS system to build, \"trips-bob\" or \"trips-cabot\"");
}

# ------------------------------------------------------------
# Perform any one-time setup.

CwcConfig::load_config(0);

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

# We are configured, go looking to see if we are up to date.
my $bin_dir = "$repo_dir/bin";
my $exe_pattern = "$bin_dir/*";

my $need_make = 0;
if (not (-d $bin_dir)) {
  $need_make = 1;
}
# elsif (not (-e $exe_filename)) {
#   $need_make = 1;
# }
else {
  # We have the target exe file. Let's figure out when it was last
  # modified and then see if we have any files newer than that in the
  # source directory.

  my $exe_mtime = undef;
  for my $exe_filename (glob($exe_pattern)) {
    if (-d $exe_filename) {
      # Don't check time on directories.
    }
    else {
      my $mtime = stat($exe_filename)->mtime;
      if ((not defined($exe_mtime)) ||
          ($mtime > $exe_mtime)) {
        $exe_mtime = $mtime;
        print("Exe ($exe_filename) last modified: $exe_mtime\n");
      }
    }
  }

  if (not defined($exe_mtime)) {
    # Didn't have any exe files, definitely need make.
    $need_make = 1;
  }
  else {
    # Had exe file time, check for newer source files.
    print("Looking for newer files.\n");
    find(sub {
           # Check if this file is newer.
         my $name = $_;

         if (-d $name) {
           # Don't check the time on directories.
         }
         else {
           my $stat = stat($name);
           (defined($stat)) or
             die("Unable to stat file: $name");

           my $mtime = $stat->mtime;
           if ($mtime > $exe_mtime) {
             print("  $mtime - $File::Find::name\n");
             $need_make = 1;
           }
         }
       }, ".");
  }
}

if ($need_make) {
  print("Looks like a build is needed.\n");

  # We need to make. Do a clean and then an install.
  my @make_clean_cmd = ("make", "clean");
  print("  " . join(" ", @make_clean_cmd) . "\n");
  if ($fix) {
    (0 == system(@make_clean_cmd)) or
      die("Failed to: " . join(" ", @make_clean_cmd));
  }

  my @make_install_cmd = ("make", "install");
  print("  " . join(" ", @make_install_cmd) . "\n");
  if ($fix) {
    (0 == system(@make_install_cmd)) or
      die("Failed to: " . join(" ", @make_install_cmd));
  }

  # Exit with non-zero exit code so that callers know we aren't
  # up-to-date.
  if (not $fix) {
    exit(1);
  }
}
else {
  print("Looks like the build is up to date.\n");
}

exit(0);

# End of main script
# ------------------------------------------------------------
# Subroutines
