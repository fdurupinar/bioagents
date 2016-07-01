#!/usr/bin/env perl

use strict;
use warnings;

use FindBin;
use lib ( $FindBin::Bin );  # for local modules
use CwcConfig;

use Cwd;
use IPC::Run;

# Autoflush stdout.
$| = 1;

# ------------------------------------------------------------
# First off, load the config.

CwcConfig::load_config(1);

# ------------------------------------------------------------
# Get to the place where we want to run.

my $bioagents_repo = CwcConfig::get_repo_config_ref("hms-bioagents");
my $bioagents_dir = $bioagents_repo->{dir};
(-d $bioagents_dir) or
  die("Bioagents directory doesn't exist: $bioagents_dir");

chdir($bioagents_dir);
print("In directory: $bioagents_dir\n");

if (exists($ENV{PYTHONPATH})) {
  $ENV{PYTHONPATH} .= ":";
}
$ENV{PYTHONPATH} .= "."; # Cwd::abs_path(".");
$ENV{PYTHONPATH} .= ":" . Cwd::abs_path("../indra");
$ENV{PYTHONPATH} .= ":" . Cwd::abs_path("../pysb");

print("PYTHONPATH=$ENV{PYTHONPATH}\n");

# ------------------------------------------------------------
# Make sure we have the drug_targets database.

my $drug_targets_db_filename =
  "$bioagents_dir/bioagents/resources/drug_targets.db";
if (not ((-e $drug_targets_db_filename) and
         (0 < -s $drug_targets_db_filename))) {
  my $drug_targets_url =
    "http://sorger.med.harvard.edu/data/bgyori/bioagents/drug_targets.db";
  my @curl_cmd =
    (
     "curl",
     # No progress bar, but yes errors.
     "-sS",
     # And fail on server errors.
     "-f",
     "-o", $drug_targets_db_filename,
     $drug_targets_url,
    );
  warn("Drug targets file ($drug_targets_db_filename) is missing or empty.");
  print("Downloading it from: $drug_targets_url\n");
  print("Using command:\n");
  print("  " . join(" ", @curl_cmd) . "\n");
  my $result = system(@curl_cmd);
  (0 == $result) or
    die("Unable to get drug_targets DB.");
}

# ------------------------------------------------------------
# Now, run DTDA.
# python dtda_module.py
#
# And MRA.
# And TRA.

my @children = ();
push(@children,
     start_child("DTDA",
                 [ "python",
                   "bioagents/dtda/dtda_module.py", ]));

push(@children,
     start_child("MRA",
                 [ "python",
                   "bioagents/mra/mra_module.py", ]));

# Set up handlers and a loop to poll the children for output and exit
# when told.
my $done = 0;

$SIG{CHLD} = $SIG{TERM} = $SIG{INT} = $SIG{QUIT} = $SIG{HUP} = $SIG{ABRT} = sub {
  my $sig = shift;
  print("got SIG$sig, will stop\n");
  $done = 1;
};

while (not $done) {
  foreach my $child (@children) {
    IPC::Run::pump_nb($child);
  }
}

print("Done, killing children.\n");

foreach my $child (@children) {
  $child->kill_kill();
}

print("Waiting for children to finish.\n");

foreach my $child (@children) {
  $child->finish();
}

print("Done with children.\n");
exit(0);

# End of main script.
# ------------------------------------------------------------
# Subroutines

sub start_child {
  my $name = shift();
  my $cmd_ref = shift();

  print("Running $name with command:\n");
  print("  " . join(" ", @$cmd_ref) . "\n");
  my $child = IPC::Run::start(\@$cmd_ref, '>pty>',
                              IPC::Run::new_chunker,
                              sub { my $in = shift();
                                    echo($name, $in);
                                    });
  return $child;
}

sub echo {
  my $name = shift();
  my $in = shift();
  # $in already includes the newline.
  print("$name: $in");
}

