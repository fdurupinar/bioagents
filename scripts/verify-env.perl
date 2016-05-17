#!/usr/bin/env perl

use strict;
use warnings;

use FindBin;
use Getopt::Long;
use IPC::Open3;
use JSON;
use Path::Class;

# ------------------------------------------------------------
# Constant values

my $CONFIG_GIT_REPOS_KEY = "git_repos";

my $NEED_CLONE = "need clone";
my $UNKNOWN = "unknown state";
my $NEED_FETCH = "need fetch";
my $NO_REMOTE = "no remote";
my $NEED_MERGE = "need merge";

# Base location of cwc-integ stuff.
my $base_dir = dir($FindBin::Bin, "..")->absolute();

# Location of conf files.
my $etc_dir = $base_dir->subdir("/etc/")->absolute();
my $default_conf_filename = $etc_dir->file("default-conf.json")->absolute();
my $local_conf_filename = $etc_dir->file("local-conf.json")->absolute();

# ------------------------------------------------------------
# Global Variables

# Set to enable verbose (debugging) output.
my $verbose = 0;

# If set, attempt to fix identified problems.
my $fix = 0;

# If set, print the fix commands instead of running them.
my $dryrun = 0;

# We populate this from the config file(s).
my %git_repos = ();
my @git_repo_names = ();

# ------------------------------------------------------------
# Parse Arguments

GetOptions('v|verbose'          => \$verbose,
           'f|fix'              => \$fix,
           'n|dry-run'          => \$dryrun,
          )
  or die("Error parsing arguments.");

# ------------------------------------------------------------
# Perform any one-time setup.

# By default, do everything from the cwc-integ root dir.
chdir($base_dir);
$verbose and
  print("Running in: " . dir(".")->absolute . "\n");

# First load the default config.
load_config($default_conf_filename);

# Then load the local config.
load_config($local_conf_filename);

# Summarize the config.
summarize_config();

# ------------------------------------------------------------
# Check each of the git repos to see if they need to be updated.

my $pass = 1;
foreach my $repo_name (@git_repo_names) {
  my $verified_repo = verify_git_repo($repo_name);
  if (not $verified_repo) {
    $pass = 0;
  }
}

# Make the exit code reflect success/failure.
if ($pass) {
  print("SUCCESS\n");
  exit(0);
}
else {
  print("FAILURE -- there are unresolved problems\n");
  exit(1);
}

# End of main script
# ------------------------------------------------------------
# Subroutines

# ------------------------------------------------------------
# Config Support

sub load_config {
  my $filename = shift();

  if(not (-e $filename)) {
    warn("Config file \"$filename\" does not exist, skipping it.");
    return;
  }

  $verbose and
    print("Reading config from: $filename\n");

  # Read the config file contents.
  my $json_text = "";
  open(my $fh, "<", $filename) or
    die("Unable to open config file: $filename");
  while(my $line = <$fh>) {
    chomp($line);
    # Remove comment-like things.
    $line =~ s/^\s*(?:#|\/\/|;).*//;
    $json_text .= $line;
  }

  # Turn it into an object.
  my $json = JSON->new();
  my $config_ref = $json->decode($json_text);

  config_git_repos($config_ref);
}

sub config_git_repos {
  my $config_ref = shift();

  if(not (defined($config_ref) and
          exists($config_ref->{$CONFIG_GIT_REPOS_KEY}))) {
    $verbose and
      print("Config did not have a \"$CONFIG_GIT_REPOS_KEY\" field, skipping it.\n");
    return;
  }

  my $repos_ref = $config_ref->{$CONFIG_GIT_REPOS_KEY};
  foreach my $repo_ref (@$repos_ref) {
    if (not exists($repo_ref->{name})) {
      warn("Config contained repo without \"name\" field, skipping repo entry.");
      next;
    }

    # Get the instance
    my $name = $repo_ref->{name};
    $verbose and
      print("Configuring repo: $name\n");
    if (not exists($git_repos{$name})) {
      $git_repos{$name} = {};
      push(@git_repo_names, $name);
    }

    # If the dir is set, use it.
    if (exists($repo_ref->{dir})) {
      my $reldir = $repo_ref->{dir};
      $verbose and
        print("  Directory: $reldir\n");
      my $dir = dir($reldir)->absolute();
      $git_repos{$name}->{dir} = $dir;
    }
  }
}

sub summarize_config {
  print("Git repos:\n");
  foreach my $name (@git_repo_names) {
    my $repo_ref = $git_repos{$name};
    my $dir = $repo_ref->{dir};
    printf("  %-20s -> $dir\n", $name);
  }
}

# ------------------------------------------------------------
# Git Interaction

# Basically, we want to verify that status like this:
#
# 1. Check for directory.
#    not exists -> need clone
#    DONE
# 2. Get ls-remote hashes.
#    no remotes -> need clone
#    DONE
# 3. Get local hash.
#    doesn't match remote -> need fetch
# 4. Get local status
#    behind -> need merge
#    ahead -> pushable
# DONE
#
# If each of the above results are returned in a list, we should loop
# over the list of actions, performing each.

sub verify_git_repo {
  my $repo_name = shift();

  $verbose and
    print("Verifying status of git repo: $repo_name\n");

  my $repo_ref = $git_repos{$repo_name};
  my @results = ();

  defined($repo_ref) or
    die("The repo ref was undefined for: $repo_name");

  my $repo_dir = $repo_ref->{dir};
  $verbose and
    print("  repo dir: $repo_dir\n");

  if (not ((-d $repo_dir) and
           (-d "$repo_dir/.git"))) {
    push(@results, $NEED_CLONE);
  }
  else {
    # Go to the repo dir and figure out what the status is.

    # We're going to change dirs, keep this so we can go back.
    my $cwd = dir(".");
    chdir($repo_dir);

    my $local_checksum = get_local_checksum();
    if (not defined($local_checksum)) {
      # If we see this, we probably need to understand what is going
      # on and update this code to handle the situation gracefully.
      warn("Local repo (in $repo_dir) doesn't have any checksum, dunno how this is possible.");
      push(@results, $UNKNOWN);
    }
    else {

      # Check to see if there are any remote changes to fetch.
      my ($remote_loc, $remote_result) = check_for_remote_changes();
      if (defined($remote_result)) {
        push(@results, $remote_result);
      }

      # Check to see if we have any local changes to merge.
      if (defined($remote_loc)) {
        my $result = check_for_local_changes();
        if (defined($result)) {
          push(@results, $result);
        }
      }
    }

    # Go back to where we were.
    chdir($cwd);
  }

  # If "fix" flag is set, try to fix the results.
  my $success = 0;
  if (0 == scalar(@results)) {
    $success = 1;
  }
  elsif ($fix) {
    $verbose and
      print("  Attempting to fix problems.\n");
    $success = fix($repo_dir, \@results);
  }

  my $result_str = "OK";
  if (0 < scalar(@results)) {
    $result_str = join(", ", @results);
  }
  printf("%-25s ... $result_str\n", $repo_name);

  return $success;
}

sub get_local_checksum {
  my @git_cmd =
    ( "git", "log",
      "--pretty=format:'%H'",
      "-n", "1"
    );
  my $in = '';
  my $git_fh;
  open3($in, $git_fh, $git_fh,
        @git_cmd) or
          die("Unable to run command: " . join(" ", @git_cmd));

  my $local_checksum = <$git_fh>;
  chomp($local_checksum);
  $verbose and
    print("  Local checksum: $local_checksum\n");

  if ($local_checksum =~ /does not have any commits yet/) {
    $local_checksum = undef;
  }
  elsif ($local_checksum =~ /^fatal/) {
    die("Unexpected error from git: $local_checksum");
  }
  else {
    # We've got it, leave the checksum alone.
  }

  return $local_checksum;
}

sub check_for_remote_changes {
  my $status;

  # Get the checksums for the remote.
  my ($remote_loc, $remote_checksum) = get_remote_info();

  if (defined($remote_checksum)) {
    $verbose and
      print("  Found remote checksum: $remote_checksum\n");

    # Try to get the date for the local commit. If we find it, we have
    # everything from the remote. If we don't find it, we are out of
    # date (and need to update).
    my $commit_date = get_commit_date($remote_checksum);

    # If we have a date for the commit, we are at least as new as the
    # the remote.
    if (defined($commit_date)) {
      # "current -- last commit: $commit_date";
    } else {
      # We don't have this commit, need to fetch from remote.
      $status = $NEED_FETCH;
    }
  }
  else {
    $status = $NO_REMOTE;
  }

  return ($remote_loc, $status);
}

# Call and output look like:
# $ git ls-remote
# From https://github.com/wdebeaum/cabot
# 89b3b0e6eed0f5a92c2a738445d535a5fdc59c36    HEAD
# 89b3b0e6eed0f5a92c2a738445d535a5fdc59c36    refs/heads/master
sub get_remote_info {
  my @git_cmd = ( "git", "ls-remote" );
  my $in = '';
  my $git_fh;
  open3($in, $git_fh, $git_fh,
        @git_cmd) or
          die("Unable to run command: " . join(" ", @git_cmd));

  # First line is the remote loc.
  my $source_line = <$git_fh>;
  chomp($source_line);
  $verbose and
    print("  Determining remote source: $source_line\n");

  my $source_loc;
  my $target_checksum;
  if ($source_line =~ /From\s+(.+)/) {
    $source_loc = $1;

    # Subsequent lines are checksums for branches. Here we just grab the
    # HEAD checksum.
    while(my $line = <$git_fh>) {
      ($line =~ /(\S+)\s+(.+)/) or
        die("Unable to parse checksum for remote: $line");
      my $checksum = $1;
      my $branch = $2;
      if ("HEAD" eq $branch) {
        $target_checksum = $checksum;
      }
    }
  }
  elsif ($source_line =~ /No remote configured to list refs from/) {
    # No remotes at all.
    # FIXME What now? Should we get the local checksum?
    # $source_loc = "local";
    # $target_checksum = get_local_checksum();
  }
  else {
    die("Unable to parse remote location: $source_line");
  }

  return ($source_loc, $target_checksum);
}

sub get_commit_date {
  my $checksum = shift();

  my @git_cmd =
    ( "git", "log",
      "--pretty=format:'%ad'",
      "-n", "1",
      $checksum,
    );
  my $in = '';
  my $git_fh;
  open3($in, $git_fh, $git_fh,
        @git_cmd) or
          die("Unable to run command: " . join(" ", @git_cmd));

  my $date = <$git_fh>;
  chomp($date);
  $verbose and
    print("  Date for $checksum: $date\n");

  if ($date =~ /bad object|unknown revision/) {
    $date = undef;
  }
  elsif ($date =~ /^fatal/) {
    die("Unexpected error from git: $date");
  }
  else {
    # We've got it, leave the date alone.
  }

  return $date;
}

sub check_for_local_changes {
  $verbose and
    print("  Checking for local changes.\n");

  # Run 'git st', output is like:
  # $ git st
  # On branch master
  # Your branch is up-to-date with 'origin/master'.
  #
  # or:
  #   On branch master
  # Your branch is behind 'origin/master' by 4 commits, and can be fast-forwarded.
  #   (use "git pull" to update your local branch)

  my @git_cmd = ( "git", "st" );
  my $in = '';
  my $git_fh;
  open3($in, $git_fh, $git_fh,
        @git_cmd) or
          die("Unable to run command: " . join(" ", @git_cmd));

  # First line is the current branch.
  my $branch_line = <$git_fh>;
  chomp($branch_line);
  $verbose and
    print("  Determining branch: $branch_line\n");

  my $branch;
  if ($branch_line =~ /On\s+branch\s+(.+)/) {
    $branch = $1;
  }

  # Next line is the status.
  my $status_line = <$git_fh>;
  chomp($status_line);
  $verbose and
    print("  Determining status: $status_line\n");

  my $remote_branch;
  my $status;
  # FIXME Make sure this works if we have unpushed local commits.
  if ($status_line =~ /Your branch is behind '(.+?)' by (\d+) commits/) {
    $remote_branch = $1;
    my $behind_by = $2;
    $verbose and
      print("  Behind by $behind_by commits\n");

    $status = $NEED_MERGE;
  }
  elsif ($status_line =~ /Your branch is up-to-date with '(.+?)'/) {
    # Up to date, nothing to do.
    $remote_branch = $1;
  }
  elsif ($status_line =~ /Changes not staged/) {
    # No remote information, apparently.
  }
  else {
    die("Unable to determine status from: $status_line");
  }

  # FIXME If we see this, we may want to return the remote branch to
  # use for checking remote (instead of assuming HEAD).
  ("origin/master" eq $remote_branch) or
    die("Tracking something other than origin/master. Probably going to have inaccurate status.");

  return $status;
}

# ------------------------------------------------------------
# Support for fixing problems

sub fix {
  my $repo_dir = shift();
  my $results_ref = shift();

  if (not $dryrun) {
    # FIXME Perform the fix.

    # Fixed, return success.
    return 1;
  }

  # Didn't fix it, do not return success.
  return 0;
}

