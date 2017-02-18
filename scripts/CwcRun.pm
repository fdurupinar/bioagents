package CwcRun;

use CwcConfig;

# ------------------------------------------------------------
# Setup

# Load the config so that we can properly find everything.
CwcConfig::load_config(0);

# ------------------------------------------------------------
# TRIPS

# Set to 1 when TRIPS has started and the facilitator is listening.
my $trips_ready = 0;

sub start_trips {
  my $which_trips = shift();
  my $no_user = shift();

  my $trips_repo_name = "trips-$which_trips";
  my $trips_repo_ref =  CwcConfig::get_git_repo_config_ref($trips_repo_name);
  defined($trips_repo_ref) or
    die("Unable to get repo configuration: $trips_repo_name");
  my $trips_dir = $trips_repo_ref->{dir};
  defined($trips_dir) or
    die("Did not find TRIPS directory in config: $trips_repo_name");
  my $trips_bin_dir = "$trips_dir/bin";
  (-d $trips_bin_dir) or
    die("TRIPS bin directory ($trips_bin_dir) doesn't exist.");
  my $trips_exe = "$trips_bin_dir/trips-$which_trips";

  my $trips = CwcRun::ipc_run(Cwd::abs_path('.'),
                              [$trips_exe, '-nouser'],
                              "TRIPS",
                              \&handle_trips_events);

  print("Waiting for TRIPS to be ready.\n");

  # Pump trips until TRIPS is ready.
  while (not $trips_ready) {
    if ($trips->pumpable()) {
      $trips->pump_nb();
    }
    else {
      # This should *not* have exited.
      die("TRIPS didn't even get started.");
    }
    sleep(0.1);
  }

  return $trips;
}

# Set a flag once TRIPS is ready.
sub handle_trips_events {
  my $in = shift();

  # CABOT and BOB report startup differently.
  if (($in =~ /facilitator: listening on port 6200/) or
      ($in =~ /comm: initialize-socket: localhost:6200/)) {
    print("TRIPS is ready.\n");
    $trips_ready = 1;
  }
}

# ------------------------------------------------------------
# General-purpose run support

# This should be used by callers who want to print partial lines of
# their own (I'm looking at you run-cwc.perl). When printing things
# like periods which show that the system is still alive, callers
# should set this to 1 so that the next output printed here will be
# printed on a new line.
#
# Output reported here resets this. So callers should set this to 1
# each time they print a partial line.
#
# This can be safely ignored by callers who don't need it.
our $need_newline = 0;

# Run a command, prefixing the output. Returns an IPC::Run handle that
# should be pumped.
sub ipc_run {
  my $working_dir = shift();
  my $cmd_ref = shift();
  my $prefix = shift();
  my $event_fn = shift();

  # Move to the desired working dir.
  my $orig_dir = Cwd::abs_path(".");
  chdir($working_dir);

  print("Running IPC command:\n");
  print("  " . join(" ", @$cmd_ref) . "\n");

  # For some reason, the chunker didn't work. I kinda wonder if some
  # crazy character code got in that interfered with the regex
  # match. Anyway, it seems to be okay for us to use a closure and
  # assemble the partial content ourselves.
  my $pending_content = "";
  my $ipc =
    IPC::Run::start($cmd_ref,
                    '<', \undef,
                    '>pty>',
                    # IPC::Run::new_chunker(qr/[\r\n]+/),
                    sub {
                      my $chunk = "$pending_content" . shift();
                      $pending_content = "";
                      my $complete = 0;
                      if ($chunk =~ /[\r\n]$/) {
                        $complete = 1;
                      }

                      my @lines = split(/[\r\n]+/, $chunk);
                      while(my $line = shift(@lines)) {
                        if ((0 == scalar(@lines)) and
                            (not $complete)) {
                          $pending_content .= $line;
                        }
                        else {
                          # If we were printing dots, make a newline
                          # before this content.
                          if ($need_newline) {
                            print("\n");
                            $need_newline = 0;
                          }

                          # If we have a prefix, print it.
                          if (defined($prefix)) {
                            print("$prefix: ");
                          }
                          print("$line\n");

                          # Check to see if the line of output should
                          # trigger anything.
                          if (defined($event_fn)) {
                            $event_fn->($line);
                          }
                        }
                      }
                    });

  # Go back to the orig dir.
  chdir($orig_dir);

  return $ipc;
}

# Evaluate to true so that the module can be loaded.
1;
