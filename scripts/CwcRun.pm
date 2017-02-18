package CwcRun;

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
