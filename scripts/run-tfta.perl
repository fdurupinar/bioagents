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
# No arguments allowed.

(0 == scalar(@ARGV)) or
  die("This script does not accept any arguments.");

# ------------------------------------------------------------
# First off, load the config.

CwcConfig::load_config(1);

# ------------------------------------------------------------
# Get to the place where we want to run.

my $tfta_dir = CwcConfig::get_repo_dir("tfta");
chdir($tfta_dir);
print("In directory: $tfta_dir\n");

CwcConfig::setup_python_path();

# ------------------------------------------------------------
# Figure out what Python to run.

my $python = "python";
my $python_version = `$python --version`;
chomp($python_version);
if ($python_version =~ /2\.7\.\d+/) {
  print("Looks like we have a suitable version of Python: $python_version\n");
}
else {
  print("Python in path wasn't a suitable version: $python_version\n");
  # Python version isn't suitable, see if python2.7 is available.
  my $which_python_27 = `which python2.7`;
  chomp($which_python_27);
  # print("$which_python_27\n");
  if (-e $which_python_27) {
    # Yeah, it's a file that exists. Use it.
    $python = "python2.7";
    print("Will use: $python\n");
  }
  else {
    print("Unable to find python2.7, expect execution to fail.\n");
  }
}

# ------------------------------------------------------------
# Now, run the agent.

my @children = ();
push(@children,
     start_child("TFTA",
                 [ "$python",
                   "tfta/tfta_module.py", ]));

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

# Hack to try to flush any remaining output.
for (my $i = 0; $i < 100; ++$i) {
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

