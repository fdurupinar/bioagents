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
my $base_dir = dir($FindBin::Bin, "..")->resolve();

# This is the config file we'll write.
my $cwc_source_config_filename = file($base_dir, "cwc-source-config.lisp")->absolute();

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
# Actually write the config file.

print("Writing config file: $cwc_source_config_filename\n");
open(my $fh, ">", $cwc_source_config_filename) or
  die("Unable to open file for writing: $cwc_source_config_filename");

# First, write a warning header.
print($fh ";; AUTO-GENERATED FILE\n");
my $script_filename = file(__FILE__)->absolute();
print($fh ";; This file was generated by: $script_filename\n");
print($fh "\n");

# Write the body of the config.
print($fh "(in-package :cl-user)\n");
print($fh "\n");

# Set up the ASDF registry.
print($fh "(require :asdf)\n");
print($fh "\n");
print($fh "(asdf:initialize-source-registry\n");
print($fh " '(:source-registry\n");

my $trips_bob_src_dir = "nil";
my $trips_cabot_src_dir = "nil";
foreach my $repo_name (CwcConfig::get_all_repo_names()) {
  my $repo_ref = CwcConfig::get_repo_config_ref($repo_name);
  if (not exists($repo_ref->{asd_search_type})) {
    # Just silently skip it.
  }
  elsif (not exists($repo_ref->{dir})) {
    warn ("Repo ($repo_name) did not have a configured directory, skipping.");
  }
  elsif (not (-d $repo_ref->{dir})) {
    die("Repo ($repo_name) was configured with missing directory: " .
        $repo_ref->{dir});
  }
  else {
    # Looks fine, add an entry to the source registry.
    my $asd_search_type = $repo_ref->{asd_search_type};
    my $repo_dir = $repo_ref->{dir};
    print($fh "    ($asd_search_type \"$repo_dir\")\n");
  }

  # If the directory exists, check to see if it is the 
  if (exists($repo_ref->{dir}) and
      (-d $repo_ref->{dir})) {
    my $src_dir = $repo_ref->{dir} . "/src";
    if (-d $src_dir) {
      if ("trips-cabot" eq $repo_name) {
        $trips_cabot_src_dir = "\"$src_dir\"";
      }
      elsif ("trips-bob" eq $repo_name) {
        $trips_bob_src_dir = "\"$src_dir\"";
      }
    }
  }
}

print($fh "   :ignore-inherited-configuration))\n");

# Store the paths to trips-bob and trips-cabot.
print($fh "\n");
print($fh "(defvar *trips-bob-src-dir* $trips_bob_src_dir)\n");
print($fh "(defvar *trips-cabot-src-dir* $trips_cabot_src_dir)\n");

exit(0);

# End of main script
# ------------------------------------------------------------
# Subroutines
