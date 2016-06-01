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

# ------------------------------------------------------------
# Fix up the classpath.

my $trips_bob_repo = CwcConfig::get_repo_config_ref("trips-bob");
my $trips_bob_dir = $trips_bob_repo->{dir};
(-d $trips_bob_dir) or
  die("TRIPS BOB directory doesn't exist: $trips_bob_dir");

my $bob_jar_dir = $trips_bob_dir . "/etc/java";
(-d $bob_jar_dir) or
  die("Didnt find expected dir for jar: $bob_jar_dir");

my $kqml_jar = "$bob_jar_dir/TRIPS.KQML.jar";
(-e $kqml_jar) or
  die("KQML jar didn't exist: $kqml_jar");

my $trips_module_jar = "$bob_jar_dir/TRIPS.TripsModule.jar";
(-e $trips_module_jar) or
  die("TripsModule jar didn't exist: $trips_module_jar");

my $util_jar = "$bob_jar_dir/TRIPS.util.jar";
(-e $util_jar) or
  die("Util jar didn't exist: $util_jar");

if (exists($ENV{CLASSPATH})) {
  $ENV{CLASSPATH} .= ":";
}
$ENV{CLASSPATH} .= "$kqml_jar";
$ENV{CLASSPATH} .= ":$trips_module_jar";
$ENV{CLASSPATH} .= ":$util_jar";

print("CLASSPATH = $ENV{CLASSPATH}\n");

if (exists($ENV{PYTHONPATH})) {
  $ENV{PYTHONPATH} .= ":";
}
$ENV{PYTHONPATH} .= "."; # Cwd::abs_path(".");
$ENV{PYTHONPATH} .= ":" . Cwd::abs_path("../indra");

print("PYTHONPATH = $ENV{PYTHONPATH}\n");

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

my @dtda_cmd =
  (
   "python",
   "bioagents/dtda/dtda_module.py",
  );

print("Running DTDA with command:\n");
print("  " . join(" ", @dtda_cmd) . "\n");
# system(@dtda_cmd);
my $dtda = IPC::Run::start(\@dtda_cmd, '>pty>', IPC::Run::new_chunker, \&dtda_echo);

my @mra_cmd =
  (
   "python",
   "bioagents/mra/mra_module.py",
  );
print("Running MRA with command:\n");
print("  " . join(" ", @mra_cmd) . "\n");
my $mra = IPC::Run::start(\@mra_cmd, '>pty>', IPC::Run::new_chunker, \&mra_echo);

# Set up handlers and a loop to poll the children for output and exit
# when told.
my $done = 0;

$SIG{CHLD} = $SIG{TERM} = $SIG{INT} = $SIG{QUIT} = $SIG{HUP} = $SIG{ABRT} = sub {
  my $sig = shift;
  print("got SIG$sig, will stop\n");
  $done = 1;
};

while (not $done) {
  IPC::Run::pump_nb($dtda);
  IPC::Run::pump_nb($mra);
}

print("Done, killing children.\n");

$dtda->kill_kill();
$mra->kill_kill();

print("Waiting for children to finish.\n");

$dtda->finish();
$mra->finish();

print("Done with children.\n");
exit(0);

# End of main script.
# ------------------------------------------------------------
# Subroutines

sub dtda_echo {
  my $in = shift();
  # $in already includes the newline.
  print("DTDA: $in");
}

sub mra_echo {
  my $in = shift();
  # $in already includes the newline.
  print("MRA: $in");
}

