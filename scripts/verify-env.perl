#!/usr/bin/env perl

use strict;
use warnings;

use FindBin;
use lib ( $FindBin::Bin );  # for local modules
use CwcConfig;

use Cwd;
use Getopt::Long;
use IPC::Open3;
use Path::Class;

# ------------------------------------------------------------
# Constant values

my $UNKNOWN = "unknown state";

my $SKIP = "skip";

my $MISSING_DIR = "missing dir";

# git problems
my $NEED_CLONE = "need clone";
my $NEED_PULL = "need pull";
my $NO_REMOTE = "no remote";
my $REMOTE_MISMATCH = "mismatched remote";
my $NEED_MERGE = "need merge";
my $AHEAD = "ahead";

# svn problems
my $NEED_CHECKOUT = "need checkout";
my $NO_URL = "no url";
my $UPDATE_WOULD_CONFLICT = "update would conflict";
my $NEED_UPDATE = "need update";

# TRIPS problems
my $NEED_CONFIGURE = "need configure";
my $NEED_MAKE = "need make";

# Base location of cwc-integ stuff.
my $base_dir = dir($FindBin::Bin, "..")->resolve();

# ------------------------------------------------------------
# Global Variables

# Set to enable verbose (debugging) output.
my $verbose = 0;

# If set, attempt to fix identified problems.
my $fix = 0;

# If set, print the fix commands instead of running them.
my $dryrun = 0;

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
  print("Running in: " . dir(".")->absolute() . "\n");

CwcConfig::load_config(1);

# ------------------------------------------------------------
# Check each of the git repos to see if they need to be updated.

print("Verifying status of git repositories.\n");
my $pass = 1;
foreach my $repo_name (CwcConfig::get_git_repo_names()) {
  my $verified_repo = verify_git_repo($repo_name);
  if (not $verified_repo) {
    $pass = 0;
  }
}

# ------------------------------------------------------------
# Check each of the svn repos to see if they need to be updated.

print("Verifying status of svn repositories.\n");
foreach my $repo_name (CwcConfig::get_svn_repo_names()) {
  my $verified_repo = verify_svn_repo($repo_name);
  if (not $verified_repo) {
    $pass = 0;
  }
}

# ------------------------------------------------------------
# Make sure that all of the required node_modules are installed and up to date.

if ($pass) {
  print("Verifying node modules.\n");
  if (not verify_node_modules()) {
    $pass = 0;
  }
}
else {
  print("Found unfixed problems, skipping attempt to verify node modules.\n");
}

# ------------------------------------------------------------
# Check the TRIPS directories, to make sure they have been made.

if ($pass) {
  print("Making sure that the TRIPS repos are built.\n");
  if (not verify_trips_built("trips-cabot")) {
    $pass = 0;
  }
  if (not verify_trips_built("trips-bob")) {
    $pass = 0;
  }
  if (not verify_trips_built("trips-cogent")) {
    $pass = 0;
  }
}
else {
  print("Found unfixed problems, skipping attempt to build TRIPS repos.\n");
}

# ------------------------------------------------------------
# If everything passed, write the configuration.

if ($pass) {
  # FIXME Make this an option and/or move the config-generation code
  # into a module.
  my @make_config_cmd =
    ( $FindBin::Bin . "/make-config.perl"
    );
  print("Making config with command: " . join(" ", @make_config_cmd) . "\n");
  (0 == system(@make_config_cmd)) or
    die("Encountered an error while making config.");
}

# ------------------------------------------------------------
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

  my $repo_ref = CwcConfig::get_git_repo_config_ref($repo_name);
  my @results = ();

  defined($repo_ref) or
    die("The repo ref was undefined for: $repo_name");

  my $repo_dir = $repo_ref->{dir};
  $verbose and
    print("  repo dir: $repo_dir\n");

  my $remote_url;
  if (exists($repo_ref->{remote_url})) {
    $remote_url = $repo_ref->{remote_url};
  }

  # Do whatever we need to do to check git status. Note that this is
  # largely duplication with verify_svn_repo.
  if (exists($repo_ref->{skip}) and
      $repo_ref->{skip}) {
    push(@results, $SKIP);
  }
  elsif (defined($remote_url) and
      not (-d "$repo_dir/.git")) {
    push(@results, $NEED_CLONE);
  }
  elsif (not (-d "$repo_dir")) {
    push(@results, $MISSING_DIR);
  }
  else {
    # Go to the repo dir and figure out what the status is.

    # We're going to change dirs, keep this so we can go back.
    my $cwd = dir(".")->absolute();
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
      if (defined($remote_url) and
          defined($remote_loc) and
          ($remote_url ne $remote_loc)) {
        push(@results, $REMOTE_MISMATCH);
      }

      if (defined($remote_result)) {
        push(@results, $remote_result);
      }

      # FIXME Should we check that $remote_loc eq $repo_ref->{remote_url}?
      # if (defined($remote_loc) and
      #     exists($repo_ref->{remote_url} and
      #     ... eq ...) {

      # Check to see if we have any local changes to merge. Only check
      # actual repo directories, otherwise we may inadvertantly report
      # status for some parent directory. Thanks, git.
      if (-d "$repo_dir/.git") {
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
  my $problem_count = print_verification_result($repo_name, \@results);

  # If "fix" flag is set, try to fix the results.
  return attempt_fix($repo_ref, $problem_count, \@results);
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
    print("    Local checksum: $local_checksum\n");

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
      print("    Found remote checksum: $remote_checksum\n");

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
    print("    Determining remote source: $source_line\n");

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
    print("    Date for $checksum: $date\n");

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
    print("    Checking for local changes.\n");

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
    print("    Determining branch: $branch_line\n");

  my $branch;
  if ($branch_line =~ /On\s+branch\s+(.+)/) {
    $branch = $1;
  }

  # Next line is the status. Get it and determine what it means to us.
  my $status_line = <$git_fh>;
  chomp($status_line);
  $verbose and
    print("    Determining status: $status_line\n");

  my $remote_branch;
  my $status;
  if ($status_line =~ /Your branch is behind '(.+?)' by (\d+)/) {
    $remote_branch = $1;
    my $behind_by = $2;
    $verbose and
      print("    Behind by $behind_by commits\n");

    $status = $NEED_MERGE;
  }
  elsif ($status_line =~ /Your branch and '(.+?)' have diverged/) {
    $remote_branch = $1;
    $verbose and
      print("    Diverged from remote\n");

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
      print("    Ahead by $ahead_by commits\n");

    $status = $AHEAD;
  }
  elsif ($status_line =~ /nothing to commit/) {
    # No remote information. We see this on Jenkins, where we are not
    # tracking a remote.
  }
  elsif ($status_line =~ /Untracked files/) {
    # Again, no remote information. We see this on Jenkins after
    # building TRIPS, where there are some generated files that are
    # not in the .gitignore list.
  }
  elsif ($status_line =~ /Changes not staged/) {
    # No remote information, apparently.
  }
  else {
    die("Unable to determine status from: $status_line");
  }

  # FIXME If we see this, we may want to return the remote branch to
  # use for checking remote (instead of assuming HEAD).
  if (not defined($remote_branch) or
      ("origin/master" eq $remote_branch)) {
    # Either we are not tracking any remote, or we are tracking the
    # origin/master. This is what we expect.
  }
  else {
    die("Tracking $remote_branch. Dunno what this means about our status.");
  }

  return $status;
}

# ------------------------------------------------------------
# Subversion Interaction

sub verify_svn_repo {
  my $repo_name = shift();

  $verbose and
    print("Verifying status of svn repo: $repo_name\n");

  my $repo_ref = CwcConfig::get_svn_repo_config_ref($repo_name);
  my @results = ();

  defined($repo_ref) or
    die("The repo ref was undefined for: $repo_name");

  my $repo_dir = $repo_ref->{dir};
  $verbose and
    print("  repo dir: $repo_dir\n");

  my $remote_url;
  if (exists($repo_ref->{remote_url})) {
    $remote_url = $repo_ref->{remote_url};
  }

  # Do whatever we need to do to check svn status. Note that this is
  # largey duplication with verify_git_repo.
  if (exists($repo_ref->{skip}) and
      $repo_ref->{skip}) {
    push(@results, $SKIP);
  }
  elsif (not (-d "$repo_dir")) {
    if (defined($remote_url)) {
      push(@results, $NEED_CHECKOUT);
    }
    else {
      push(@results, $MISSING_DIR);
    }
  }
  else {
    # Figure out what the status is.
    my ($remote_loc, $remote_result) = check_for_repo_changes($repo_dir);
    if (defined($remote_url) and
        defined($remote_loc) and
        ($remote_url ne $remote_loc)) {
      push(@results, $REMOTE_MISMATCH);
    }

    if (defined($remote_result)) {
      push(@results, $remote_result);
    }
  }

  # Prepare and print the result statement.
  my $problem_count = print_verification_result($repo_name, \@results);

  # If "fix" flag is set, try to fix the results.
  return attempt_fix($repo_ref, $problem_count, \@results);
}

sub check_for_repo_changes {
  my $repo_dir = shift();
  my $status;

  my $remote_loc = get_repo_url($repo_dir);
  if (defined($remote_loc)) {
    # Had a remote, check for changes to merge.
    $status = get_merge_status($repo_dir);

    # FIXME We might also want to check for local changes that we need
    # to commit.
  }
  else {
    $status = $NO_URL;
  }

  return ($remote_loc, $status);
}

sub get_repo_url {
  my $repo_dir = shift();

  my @svn_cmd = ( "svn", "info",
                  $repo_dir );
  my $in = '';
  my $svn_fh;
  open3($in, $svn_fh, $svn_fh,
        @svn_cmd) or
          die("Unable to run command: " . join(" ", @svn_cmd));

  while (my $line = <$svn_fh>) {
    chomp($line);
    if ($line =~ /^URL:\s+(.+)/) {
      my $remote_loc = $1;
      return $remote_loc;
    }
  }

  # die("Unable to determine remote location for repo: $repo_name");
  return undef;
}

sub get_merge_status {
  my $repo_dir = shift();

  my @svn_cmd = ( "svn", "status",
                  "--show-updates",
                  $repo_dir );
  my $in = '';
  my $svn_fh;
  open3($in, $svn_fh, $svn_fh,
        @svn_cmd) or
          die("Unable to run command: " . join(" ", @svn_cmd));

  my $need_update = 0;
  while (my $line = <$svn_fh>) {
    chomp($line);
    if ($line =~ /^\s*\*\s+(.+?)\s+(.+)/) {
      my $rev = $1;
      my $filename = $2;
      ++$need_update;
    }
  }

  my $status;
  if ($need_update) {
    if (would_update_conflict($repo_dir)) {
      $status = $UPDATE_WOULD_CONFLICT;
    }
    else {
      $status = $NEED_UPDATE;
    }
  }
  return $status;
}

sub would_update_conflict {
  my $repo_dir = shift();

  # First, go to the working directory.
  my $cwd = dir(".")->absolute();
  chdir($repo_dir);

  my @svn_cmd = ( "svn", "merge",
                  "--dry-run",
                  "-r", "BASE:HEAD",
                  # For some reason, the merge command must be in the
                  # repo dir.
                  "." );
  $verbose and
    print("Checking for conflict using command: " . join(" ", @svn_cmd) . "\n");
  my $in = '';
  my $svn_fh;
  open3($in, $svn_fh, $svn_fh,
        @svn_cmd) or
          die("Unable to run command: " . join(" ", @svn_cmd));

  my $would_conflict = 0;
  while (my $line = <$svn_fh>) {
    chomp($line);
    if ($line =~ /^Summary of conflicts:/) {
      $would_conflict = 1;
    }
  }

  # Go back to where we were.
  chdir($cwd);

  return $would_conflict;
}

# ------------------------------------------------------------
# Node module support

sub verify_node_modules {
  my $all_verified = 1;

  my $plexus_repo_ref = CwcConfig::get_repo_config_ref("plexus");
  my $plexus_dir = $plexus_repo_ref->{dir};
  if (not verify_node_modules_installed($plexus_dir)) {
    $all_verified = 0;
  }

  my $spire_repo_ref = CwcConfig::get_repo_config_ref("spire");
  my $spire_plexus_dir = $spire_repo_ref->{dir} . "/plexus";
  if (verify_node_modules_installed($spire_plexus_dir)) {
    # Verify the symlinks.
    if (not verify_node_symlink($spire_plexus_dir, "plexus", $plexus_dir)) {
      $all_verified = 0;
    }
  }
  else {
    $all_verified = 0;
  }

  my $clic_repo_ref = CwcConfig::get_repo_config_ref("clic");
  my $clic_plexus_dir = $clic_repo_ref->{dir} . "/plexus";
  if (verify_node_modules_installed($clic_plexus_dir)) {
    # Verify the symlinks.
    if (not verify_node_symlink($clic_plexus_dir, "plexus", $plexus_dir)) {
      $all_verified = 0;
    }
    if (not verify_node_symlink($clic_plexus_dir, "spire-plexus", $spire_plexus_dir)) {
      $all_verified = 0;
    }
  }
  else {
    $all_verified = 0;
  }

  my $sbgnviz_repo_ref = CwcConfig::get_repo_config_ref("sbgnviz");
  my $sbgnviz_dir = $sbgnviz_repo_ref->{dir};
  if (not verify_node_modules_installed($sbgnviz_dir)) {
    $all_verified = 0;
  }

  my $sbgnviz_public_dir = $sbgnviz_dir . "/public";
  if (not verify_node_modules_installed($sbgnviz_dir)) {
    $all_verified = 0;
  }

  return $all_verified;
}

sub verify_node_modules_installed {
  my $dir = shift();

  print("  $dir\n");
  if ($fix) {
    print("    Running 'npm install'\n");
    my $success = run_fix_command($dir,
                                  ["npm", "install"]);
    if (not $success) {
      return 0;
    }
  }
  elsif (not -d "$dir/node_modules") {
    print("    node_modules directory missing.\n");
    return 0;
  }

  # node_modules existed, assume that it's okay?
  return 1;
}

sub verify_node_symlink {
  my $project_dir = shift();
  my $module_name = shift();
  my $expected_link_target = shift();

  my $link_okay = 0;

  my $link_name = "$project_dir/node_modules/$module_name";
  if (-e $link_name) {
    # It exists. We won't overwrite it, so either it's okay or we'll
    # fail.
    my $link_target = readlink $link_name;

    my $expected_link_target_quoted = quotemeta $expected_link_target;
    my $expected_link_target_regex = qr/^$expected_link_target_quoted(?:\/?)$/;
    if (-l $link_name and
        ($link_target =~ $expected_link_target_regex)) {
      $link_okay = 1;
    }
    else {
      print("    Node module ($module_name) exists in: $project_dir/node_modules\n");
      print("      but isn't a symlink to: $expected_link_target\n");
      $link_okay = 0;
    }
  }
  else {
    print("    Missing node module symlink: $link_name\n");
    if ($fix) {
      $link_okay = symlink($expected_link_target, $link_name);
    }
  }
  return $link_okay;
}

# ------------------------------------------------------------
# Support for building TRIPS

sub verify_trips_built {
  my $repo_name = shift();
  my $repo_ref = CwcConfig::get_repo_config_ref($repo_name);

  if (exists($repo_ref->{skip}) and
      $repo_ref->{skip}) {
    # Treat skip as a success.
    return 1;
  }

  # Check to see if an update is needed.
  my @trips_cmd = ($FindBin::Bin . "/verify-trips-build.perl",
                   $repo_name);

  $verbose and
    print("Checking for need to make TRIPS using command: " . join(" ", @trips_cmd) . "\n");
  my $in = '';
  my $trips_fh;
  open3($in, $trips_fh, $trips_fh,
        @trips_cmd) or
          die("Unable to run command: " . join(" ", @trips_cmd));

  my @results = ();
  my $need_config = 0;
  while (my $line = <$trips_fh>) {
    chomp($line);
    if ($verbose or $need_config) {
      print("$line\n");
    }

    if ($line =~ /Need to configure TRIPS/) {
      push(@results, $NEED_CONFIGURE);
      $need_config = 1;
    }
    elsif ($line =~ /Looks like a build is needed/) {
      push(@results, $NEED_MAKE);
    }
  }

  # Prepare and print the result statement.
  my $problem_count = print_verification_result($repo_name, \@results);

  # If "fix" flag is set, try to fix the results.
  return attempt_fix($repo_ref, $problem_count, \@results);
}

# ------------------------------------------------------------
# Support for printing results

sub print_verification_result {
  my $repo_name = shift();
  my $results_ref = shift();

  my $result_str = "";
  my $problem_count = 0;
  foreach my $result (@$results_ref) {
    if (0 < $problem_count) {
      $result_str .= ", ";
    }
    $result_str .= $result;

    if ($SKIP eq $result) {
      # Told to skip it. We're still fine.
    }
    elsif ($AHEAD eq $result) {
      # Just a warning. We're still okay.
    }
    else {
      ++$problem_count;
    }
  }

  my $prob_str;
  if (0 == $problem_count) {
    $prob_str = "OK";
  }
  elsif (1 == $problem_count) {
    $prob_str = "1 problem";
  }
  else {
    $prob_str = "$problem_count problems";
  }
  printf("  %-25s %-12s... %-20s\n",
         $repo_name, $prob_str, $result_str);

  return $problem_count;
}

# ------------------------------------------------------------
# Support for fixing problems

sub attempt_fix {
  my $repo_ref = shift();
  my $problem_count = shift();
  my $results_ref = shift();

  my $success = 0;
  if (0 == $problem_count) {
    $success = 1;
  }
  elsif ($fix) {
    $verbose and
      print("    Attempting to fix problems.\n");
    $success = fix($repo_ref, $results_ref);
    if ($success) {
      print("    FIXED\n");
    }
    else {
      print("    NOT fixed\n");
    }
  }

  return $success;
}

sub fix {
  my $repo_ref = shift();
  my $results_ref = shift();

  exists($repo_ref->{dir}) or
    die("For some reason we are trying to repair a repo that doesn't have a directory.");

  my $repo_dir = dir($repo_ref->{dir});

  my $fixed_all = 1;
  foreach my $result (@$results_ref) {
    $verbose and
      print("    Trying to fix: $result\n");

    if ($result eq $MISSING_DIR) {
      $repo_dir->mkpath();
    }
    elsif ($result eq $NEED_CLONE) {
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
    elsif ($result eq $NEED_CHECKOUT) {
      if (exists($repo_ref->{remote_url})) {
        my $remote_url = $repo_ref->{remote_url};
        if (not run_fix_command(".",
                                ["svn", "checkout",
                                 $remote_url,
                                 $repo_dir])) {
          $fixed_all = 0;
        }
      }
      else {
        warn("Cannot fix repo with checkout, no remote_url in config.");
        $fixed_all = 0;
      }
    }
    elsif ($result eq $NEED_UPDATE) {
      if (not run_fix_command(".",
                              ["svn", "up",
                               $repo_dir])) {
        $fixed_all = 0;
      }
    }
    elsif ($result eq $NEED_CONFIGURE) {
      # Make a warning, but don't fail this. We don't want this to
      # break Jenkins itself until after we have verified that the
      # compile should be successful.
      #
      # Likewise, until we have the TRIPS-dependent code under test,
      # most developers don't need TRIPS built either.
      my $repo_name = $repo_ref->{name};
      warn("Need to manually execute configure command for $repo_name.");
      $fixed_all = 0;
    }
    elsif ($result eq $NEED_MAKE) {
      my $repo_name = $repo_ref->{name};
      if (not run_fix_command(".",
                              [$FindBin::Bin . "/verify-trips-build.perl",
                               $repo_name,
                               "--fix"])) {
        $fixed_all = 0;
      }
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
  my $cwd = dir(".")->absolute();
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

