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

my $sbgnviz_dir = CwcConfig::get_repo_dir("sbgnviz");
chdir($sbgnviz_dir);
print("In directory: $sbgnviz_dir\n");

# ------------------------------------------------------------
# Now, run sbgnviz

my @children = ();
push(@children,
     start_child("sbgnviz", ["node", "server.js"]));

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

