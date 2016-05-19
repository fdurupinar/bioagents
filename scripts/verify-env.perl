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
my $NEED_PULL = "need pull";
my $NO_REMOTE = "no remote";
my $NEED_MERGE = "need merge";
my $AHEAD = "ahead";

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

    # If the remote_url is set, use it.
    if (exists($repo_ref->{remote_url})) {
      my $remote_url = $repo_ref->{remote_url};
      $verbose and
        print("  Remote URL: $remote_url\n");
      $git_repos{$name}->{remote_url} = $remote_url;
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
#    doesn't match remote -> need pull
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

      # Check to see if there are any remote changes to get.
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

  # Prepare and print the result statement.
  my $result_str = "";
  my $problem_count = 0;
  foreach my $result (@results) {
    if (0 < $problem_count) {
      $result_str .= ", ";
    }
    $result_str .= $result;

    if ($AHEAD eq $result) {
      # Just a warning. We're still okay.
    }
    else {
      ++$problem_count;
    }
  }
  printf("%-25s ... %-20s", $repo_name, $result_str);
  if (0 == $problem_count) {
    print("OK\n");
  }
  elsif (1 == $problem_count) {
    print("1 problem\n");
  }
  else {
    print("$problem_count problems\n");
  }

   # If "fix" flag is set, try to fix the results.
  my $success = 0;
  if (0 == scalar(@results)) {
    $success = 1;
  }
  elsif ($fix) {
    $verbose and
      print("  Attempting to fix problems.\n");
    $success = fix($repo_ref, \@results);
    if ($success) {
      print("  FIXED\n");
    }
    else {
      print("  NOT fixed\n");
    }
  }

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
      # We don't have this commit, need to pull from remote.
      $status = $NEED_PULL;
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
  # On branch master
  # Your branch is behind 'origin/master' by 4 commits, and can be fast-forwarded.
  #   (use "git pull" to update your local branch)
  #
  # or:
  # On branch master
  # Your branch is ahead of 'origin/master' by 3 commits.
  #   (use "git push" to publish your local commits)
  #
  # or:
  # On branch master
  # Your branch and 'origin/master' have diverged,
  # and have 3 and 1 different commit each, respectively.
  #   (use "git pull" to merge the remote branch into yours)

  my @git_cmd = ( "git", "status" );
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

  # Next line is the status. Get it and determine what it means to us.
  my $status_line = <$git_fh>;
  chomp($status_line);
  $verbose and
    print("  Determining status: $status_line\n");

  my $remote_branch;
  my $status;
  if ($status_line =~ /Your branch is behind '(.+?)' by (\d+)/) {
    $remote_branch = $1;
    my $behind_by = $2;
    $verbose and
      print("  Behind by $behind_by commits\n");

    $status = $NEED_MERGE;
  }
  elsif ($status_line =~ /Your branch and '(.+?)' have diverged/) {
    $remote_branch = $1;
    $verbose and
      print("  Diverged from remote\n");

    $status = $NEED_MERGE;
  }
  elsif ($status_line =~ /Your branch is up-to-date with '(.+?)'/) {
    # Up to date, nothing to do.
    $remote_branch = $1;
  }
  elsif ($status_line =~ /Your branch is ahead of '(.+?)' by (\d+)/) {
    $remote_branch = $1;
    my $ahead_by = $2;
    $verbose and
      print("  Ahead by $ahead_by commits\n");

    $status = $AHEAD;
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
  my $repo_ref = shift();
  my $results_ref = shift();

  exists($repo_ref->{dir}) or
    die("For some reason we are trying to repair a repo that doesn't have a directory.");

  my $repo_dir = dir($repo_ref->{dir});

  my $fixed_all = 1;
  foreach my $result (@$results_ref) {
    $verbose and
      print("  Trying to fix: $result\n");

    if ($result eq $NEED_CLONE) {
      # git clone
      if (exists($repo_ref->{remote_url})) {
        my $remote_url = $repo_ref->{remote_url};
        my $success = run_fix_command($repo_dir->parent(),
                                      ["git", "clone", $remote_url]);
        if (not $success) {
          $fixed_all = 0;
        }
      }
      else {
        warn("Cannot fix repo by cloning, no remote_url in config.");
        $fixed_all = 0;
      }
    }
    elsif ($result eq $NEED_PULL) {
      # git pull --ff-only
      if (not run_fix_command($repo_dir,
                              ["git", "pull", "--ff-only"])) {
        $fixed_all = 0;
      }
    }
    elsif ($result eq $NO_REMOTE) {
      # Unfixable... I think. Even if we have a URL in the config,
      # what would we do here, git add the remote? Then what? Would we
      # need to recheck the fixes?
      $fixed_all = 0;
      warn("Unable to fix repo with no remote.");
    }
    elsif ($result eq $NEED_MERGE) {
      # git merge --ff-only
      if (not run_fix_command($repo_dir,
                              ["git", "merge", "--ff-only"])) {
        $fixed_all = 0;
      }
    }
    elsif ($result eq $AHEAD) {
      # FIXME We don't need to do anything to fix this. But perhaps
      # print a message suggesting to push.
    }
    else {
      # Dunno what to do. Warn the user and punt.
      $fixed_all = 0;
      warn("Don't know how to fix problem: $result");
    }
  }

  return $fixed_all;
}

sub run_fix_command {
  my $working_dir = shift();
  my $cmd_ref = shift();

  # First, make sure the directory exists. Call mkpath if necessary.
  if (not (-e $working_dir)) {
    print("  make directory: $working_dir\n");
    if ($dryrun) {
      # Don't do anything for the dry-run.
    }
    else {
      $working_dir->mkpath();
    }
  }

  # First, go to the working directory.
  my $cwd = dir(".");
  chdir($working_dir);

  print("  cd $working_dir\n");
  print("     " . dir(".")->absolute() . "\n");
  print("  " . join(" ", @$cmd_ref) . "\n");
  my $success = 0;
  if ($dryrun) {
    # Don't do anything for the dry run.
  }
  else {
    # Run the command.
    my $exit_code = system(@$cmd_ref);
    if (0 == $exit_code) {
      # Success.
      $success = 1;
    }
  }

  # Go back to where we were.
  chdir($cwd);

  # Let the caller know if this succeeded.
  return $success;
}

