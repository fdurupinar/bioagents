# Communicating with Computers Integration
This is top-level projects organizes CwC integration and demo efforts.

# Getting Started
Please note, if any of the Perl scripts fail with an indication that
they cannot find a library, look at the
[Perl Libraries](#perl-libraries) section below for guidance on how to
install the missing library.

1. Clone the cwc-integ project.
    ```
git clone https://gitlab.com/cwc/cwc-integ.git
```

2. Download or check out the SHOP2 HTN planner.

    The SHOP2 planner is maintained in an svn repo at SIFT. If you
    have credentials for this repo, you can check it out as in:
    ```
cd cwc-integ
svn co https://svn.sift.net:3333/svn/shop2/shop/trunk/shop2
```

    Otherwise, you can download the stable release from SourceForge --
    https://sourceforge.net/projects/shop/. Uncompress the release
    into the ```cwc-integ/shop2``` directory.

3. [Optional] Create an ```etc/local-conf.json``` file with custom
   settings. See [below](#custom-environment-setup) for details.

4. Verify that your environment is set up properly. Fix it if
   necessary.

    The first time you run this, the script will clone a bunch of git
    repos and check out some svn repos. After that, running this
    script should only update the local copy when remote changes are
    found.
    ```
cd cwc-integ
scripts/verify-env.perl --fix
```

5. Run the tests to verify that everything is working. The Jenkins
   script always runs ```verify-env.perl --fix```, so the tests should
   always run against an up-to-date environment.
    ```
cd cwc-integ
scripts/jenkins.perl
```

# Perl Libraries
The Perl scripts in this project have several external
dependencies. These must be manually installed on each developer
machine. If you run a script and it gives an error that it can't find
a library (such as Path::Class or JSON), you should manually install
the library and try again.

On most Perl implementations, you should be able to install missing
libraries using the CPAN shell. As in:
```
sudo perl -MCPAN -e shell
CPAN> install Path::Class
```

Alternatively, on a Debian server at SIFT we sometimes install the
libraries using the system package manager instead, as in:
```
aptitude install libpath-class-perl
```

There may be other modules, but you definitely need to have:
- ```JSON```
- ```Path::Class``` / ```libpath-class-perl```
- ```Proc::Killfam``` / ```libproc-processtable-perl```

# Supported Lisp Implementations
Many CwC components are written in Lisp. We only officially support
SBCL, though we have made some effort to also support CCL.

# Custom Environment Setup
The default configuration puts all the required projects into
appropriate subdirectories. Realistically, each developer may organize
their projects separately. For instance, the IHMC TRIPS code is
officially managed in a CVS repository and pushed to git overnight as
appropriate. During daily development, IHMC developers will want to
use a working copy of their CVS repo instead of a clone of the git
repo.

The verify script reads its configuration from two files:
- ```etc/default-conf.json``` and
- ```etc/local-conf.json```.

The default config is maintained in git and is read first. The local
config is ignored by git and loaded after the default config to
override default values.

Here is an example of what a ```etc/local-conf.json``` file might look
like for an IHMC developer.
```
// As with the default conf, comments can start with # or // and are
// only counted when they are the only content on the line.
{
    "git_repos": [
        // Use the local versions of TRIPS. 
        { "name": "trips-cabot",
          // Setting a value here overwrites the value from the
          // default config. Note that the path does not need to be a
          // subdirectory of cwc-integ.
          "dir": "~/projects/trips/cabot",
          // Setting the skip value to true will cause this repo to
          // be skipped during verification. It will be assumed to be
          // up-to-date.
          "skip": true },
        { "name": "trips-bob",
          "dir": "~/projects/trips/bob",
          "skip": true }
    ]
}
```

# Development
During normal development, there are some tools you can use to ensure
that the integrated system continues to work for everyone.

## ```scripts/verify-env.perl```
The verify-env script reads its configuration from
```etc/default-conf.json``` and ```etc/local-conf.json```, then
performs some checks to see if the directories/repos identified in the
config are up to date.

If verify-env.perl finds any problems, you can usually automatically
fix them by running:
```
verify-env.perl --fix
```

The verify-env script will automatically mkdir, clone, pull
(--ff-only), and merge (--ff-only), as necessary to try to fix the
problems it finds.

The verify-env script also calls the make-config.perl script to write
a lisp file that can be used to set up the ASDF registry before
loading the required systems.

You can run verify-env.perl from anywhere -- it acts in root cwc-integ
directory.

## ```scripts/make-config.perl```
Reads the same config files as the verify-env script. Creates the
```cwc-source-config.lisp``` file in the root of the cwc-integ
project.

Loading this file initializes ASDF's source registry to find the
projects that are part of this integration.

## ```scripts/jenkins.perl```
Please run the jenkins script before pushing changes. If the jenkins
script passes for you locally, hopefully the changes you push will
work for other developers as well.

As noted in the Getting Started section above, the jenkins script runs
```verify-env.perl``` with the ```--fix``` argument and then runs the
known tests.

## ```scripts/run-test.perl```
The run-test script runs a single test. You can run tests as in:
```
scripts/run-test.perl :spire
scripts/run-test.perl :spire/test-sparser
```

# Git Tips
If git repeatedly asks for credentials to access GitLab repos, you may
want to add the following to your ```~/.gitconfig``` file.

For Mac OSX:
```
[credential]
    helper = osxkeychain
```

For Debian -- but note that this will store your credentials
unencrypted, in ~/.git-credentials, protected only by file-system
permissions.
```
[credential]
    helper = store
```

