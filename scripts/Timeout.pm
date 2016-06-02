package Timeout;

use POSIX;
use Proc::Killfam;

my $process_group;

sub fork_timeout_process {
  my $timeout_s = shift();
  defined($timeout_s) or
    $timeout_s = 0;

  # Fork a child to form its own process group. The parent will sit
  # around for a specified timeout. If the timeout is reached, it
  # signals the child and we exit.

  if (0 != $timeout_s) {
    print("Setting timeout for $timeout_s s.\n");
  }

  my $child = fork();
  if (0 < $child) {
    # I'm the parent. Set a SIGCHILD handler so that our sleep can be
    # interrupted. Sleep for a while, then have the child shutdown.
    $SIG{CHLD} = sub{
      my $pid = wait();
      # print("Child ($pid) exited.\n");
      if ($child == $pid) {
        my $exit_code = $?;
        # Shift to the right by 8 to get the exit code.
        $exit_code = $exit_code >> 8;
        # print("Child exit code was: $exit_code\n");
        exit($exit_code);
      }
    };

    # Pass signals through to child.
    $SIG{TERM} = $SIG{INT} = $SIG{QUIT} = $SIG{HUP} = $SIG{ABRT} = sub {
      my $sig = shift;
      print("got SIG$sig, passing on to child ($child)\n");
      kill($sig, $child);
    };

    if (0 != $timeout_s) {
      sleep($timeout_s);
      print("Done sleeping, time to die.\n");
      kill('USR1', $child);
    }

    # We sleep indefinitely, because the SIGCHLD handler will exit.
    print("Waiting for child ($child).\n");
    while (1) {
      sleep(1);
    }

    die("I don't know what happened, I don't think we should have gotten here...\n");
  } elsif (0 > $child) {
    die("Error forking child for timeout.");
  }

  # I'm the child. Setup a signal handler and proceed with doing all
  # the work...
  $process_group = POSIX::setsid();
  print("I ($$) am the child, and have become process group: $process_group\n");

  # This will be set to 1 if we time out.
  my $timed_out = 0;
  $SIG{USR1} = sub {
    print("------------------------------------------------------------\n");
    # print("Timed out after $timeout_s seconds.\n");
    print("I (the child process) was given SIGUSR1.\n");
    # print("Sending TERM to process group: $process_group\n");
    # $SIG{TERM} = 'IGNORE';
    # # This assumes that all children will die gracefully in response to SIGTERM,
    # # but zombie children may still persist if signal is ignored.
    # #
    # # [jrye:20160602.1606CST] This doesn't seem to kill TRIPS
    # # processes. Ugh. I'll just use the killfam library and call it
    # # good.
    # #
    # # kill(-15, $process_group);
    # killfam(15, $process_group);

    $timed_out = 1;
    exit(1);
  };

  # This will be set to the signal name if we are killed. Not sure we
  # actually need it though.
  my $killed = "";
  $SIG{'TERM'} = $SIG{'INT'} = $SIG{'QUIT'} = $SIG{'HUP'} = $SIG{'ABRT'} = sub {
    my $sig = shift;
    print("got SIG$sig\n");
    # print("got SIG$sig, Sending TERM to process group ($process_group)\n");
    # $SIG{'TERM'} = 'IGNORE';
    # # kill(-15, $process_group);
    # killfam(15, $process_group);

    $killed = $sig;
    exit(1);
  };
}

END {
  if (defined($process_group)) {
    print("Exiting, sending TERM to process group.\n");
    $SIG{TERM} = 'IGNORE';
    killfam(15, $process_group);
  }
}

# Evaluate to true so that the module can be loaded.
1;
