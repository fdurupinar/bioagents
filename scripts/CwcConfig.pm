package CwcConfig;

use strict;
use warnings;

use JSON;
use Path::Class;

# ------------------------------------------------------------
# Constant values

my $CONFIG_GIT_REPOS_KEY = "git_repos";
my $CONFIG_SVN_REPOS_KEY = "svn_repos";

# Base location of cwc-integ stuff.
my $base_dir = dir($FindBin::Bin, "..")->resolve();

# Location of conf files.
my $etc_dir = $base_dir->subdir("/etc/")->absolute();
my $default_conf_filename = $etc_dir->file("default-conf.json")->absolute();
my $local_conf_filename = $etc_dir->file("local-conf.json")->absolute();

# ------------------------------------------------------------
# Module variables

# We populate these from the config file(s).
my %git_repos = ();
my @git_repo_names = ();

my %svn_repos = ();
my @svn_repo_names = ();

# ------------------------------------------------------------
# Accessors

sub get_git_repo_names {
  return @git_repo_names;
}

sub get_git_repo_config_ref {
  my $repo_name = shift();
  if (exists($git_repos{$repo_name})) {
    return $git_repos{$repo_name};
  }
  else {
    return undef;
  }
}

sub get_svn_repo_names {
  return @svn_repo_names;
}

sub get_svn_repo_config_ref {
  my $repo_name = shift();
  if (exists($svn_repos{$repo_name})) {
    return $svn_repos{$repo_name};
  }
  else {
    return undef;
  }
}

sub get_all_repo_names {
  my @all_repo_names = ();
  push(@all_repo_names, @git_repo_names);
  push(@all_repo_names, @svn_repo_names);
  return @all_repo_names;
}

sub get_repo_config_ref {
  my $repo_name = shift();

  my $git_repo_config_ref = get_git_repo_config_ref($repo_name);
  my $svn_repo_config_ref = get_svn_repo_config_ref($repo_name);
  if (defined($git_repo_config_ref)) {
    if (defined($svn_repo_config_ref)) {
      die("Found both git and svn configs for: $repo_name");
    }
    else {
      return $git_repo_config_ref;
    }
  }
  elsif (defined($svn_repo_config_ref)) {
    return $svn_repo_config_ref;
  }
  else {
    die("Unable to find config for: $repo_name");
  }
}


# ------------------------------------------------------------
# Config loading functions

sub load_config {
  my $summarize = shift();

  # First load the default config.
  load_config_file($default_conf_filename);

  # Then load the local config.
  load_config_file($local_conf_filename);

  if ($summarize) {
    # Summarize the config.
    summarize_config();
  }
}

sub load_config_file {
  my $filename = shift();

  if(not (-e $filename)) {
    # warn("Config file \"$filename\" does not exist, skipping it.");
    return;
  }

  # $verbose and
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

  if (defined($config_ref)) {
    if (exists($config_ref->{$CONFIG_GIT_REPOS_KEY})) {
      store_repo_configs($config_ref->{$CONFIG_GIT_REPOS_KEY},
                         \@git_repo_names,
                         \%git_repos);
    }

    if (exists($config_ref->{$CONFIG_SVN_REPOS_KEY})) {
      store_repo_configs($config_ref->{$CONFIG_SVN_REPOS_KEY},
                         \@svn_repo_names,
                         \%svn_repos);
    }
  }
}

sub store_repo_configs {
  my $repos_ref = shift();
  my $repo_names_ref = shift();
  my $repo_configs_ref = shift();
  
  foreach my $repo_ref (@$repos_ref) {
    if (not exists($repo_ref->{name})) {
      warn("Config contained repo without \"name\" field, skipping repo entry.");
      next;
    }

    # Get the instance
    my $name = $repo_ref->{name};
    $main::verbose and
      print("Configuring repo: $name\n");
    if (not exists($repo_configs_ref->{$name})) {
      $repo_configs_ref->{$name} = {};
      push(@$repo_names_ref, $name);
    }

    my $repo_config_ref = $repo_configs_ref->{$name};
    foreach my $key (keys(%$repo_ref)) {
      my $val = $repo_ref->{$key};

      if ("dir" eq $key) {
        # Treat this as a directory. Find it relative to the config
        # file.

        # Attempt to do globbing in case the user included a ~ or
        # something. Only accept the globbed answer if there was
        # exactly one match.
        my $path = $val;
        my @expansions = glob($val);
        if (1 == scalar(@expansions)) {
          $path = $expansions[0];
        }
        my $dir = dir($path)->absolute();

        $main::verbose and
          print("  Directory: $val => $dir\n");
        $repo_config_ref->{$key} = $dir;
      }
      else {
        # Just store the value and be happy.
        $repo_config_ref->{$key} = $val;
      }
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

  print("Subversion repos:\n");
  foreach my $name (@svn_repo_names) {
    my $repo_ref = $svn_repos{$name};
    my $dir = $repo_ref->{dir};
    printf("  %-20s -> $dir\n", $name);
  }
}

# ------------------------------------------------------------
# Setup stuff shared between Python-based agents (e.g., run-bioagents
# and run-tfta).

sub get_repo_dir {
  my $repo_name = shift();

  my $repo_ref = CwcConfig::get_repo_config_ref($repo_name);
  defined($repo_name) or
    die("Repo wasn't defined: $repo_name");

  my $repo_dir = $repo_ref->{dir};
  (-d $repo_dir) or
    die("Repo directory doesn't exist: $repo_dir");

  return $repo_dir;
}

sub setup_python_path {
  if (exists($ENV{PYTHONPATH})) {
    $ENV{PYTHONPATH} .= ":";
  }
  $ENV{PYTHONPATH} .= "."; # Cwd::abs_path(".");
  $ENV{PYTHONPATH} .= ":" . Cwd::abs_path(get_repo_dir("hms-indra"));
  $ENV{PYTHONPATH} .= ":" . Cwd::abs_path(get_repo_dir("hms-pysb"));
  $ENV{PYTHONPATH} .= ":" . Cwd::abs_path(get_repo_dir("hms-kqml"));

  print("PYTHONPATH=$ENV{PYTHONPATH}\n");
}


# Evaluate to true so that the module can be loaded.
1;
