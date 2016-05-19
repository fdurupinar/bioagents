package CwcConfig;

use JSON;
use Path::Class;

# ------------------------------------------------------------
# Constant values

my $CONFIG_GIT_REPOS_KEY = "git_repos";

# Base location of cwc-integ stuff.
my $base_dir = dir($FindBin::Bin, "..")->resolve();

# Location of conf files.
my $etc_dir = $base_dir->subdir("/etc/")->absolute();
my $default_conf_filename = $etc_dir->file("default-conf.json")->absolute();
my $local_conf_filename = $etc_dir->file("local-conf.json")->absolute();

# ------------------------------------------------------------
# Module variables

# We populate this from the config file(s).
my %git_repos = ();
my @git_repo_names = ();

# ------------------------------------------------------------
# Accessors

sub get_git_repo_names {
  return @git_repo_names;
}

sub get_git_repo_config_ref {
  my $repo_name = shift();
  return $git_repos{$repo_name};
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

    foreach my $key (keys(%$repo_ref)) {
      my $val = $repo_ref->{$key};

      if ("dir" eq $key) {
        # Treat this as a directory. Find it relative to the config
        # file.
        my $dir = dir($val)->absolute();
        $verbose and
          print("  Directory: $val => $dir\n");
        $git_repos{$name}->{$key} = $dir;
      }
      else {
        # Just store the value and be happy.
        $git_repos{$name}->{$key} = $val;
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
}

# Evaluate to true so that the module can be loaded.
1;
