# Communicating with Computers Integration
This is top-level projects organizes CwC integration and demo efforts.

# Getting Started
The most basic way to get started is to clone the cwc-integ project
and run the jenkins script. The jenkins script verifies that the
required projects and libraries are present, cloning and updating them
as necessary. Then it runs some tests, reporting results and timing
information.

If this (or any of the other Perl scripts) fails with an indication
that it cannot find a library, look at the ~perl-libraries section below
for guidance on how to install the missing library.

```
git clone https://gitlab.com/cwc/cwc-integ.git
cd cwc-integ
scripts/jenkins.perl
```

# Requirements

## Perl Libraries
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

On a Debian server at SIFT we sometimes install the libraries using
the system package manager instead, as in:
```
aptitude install libpath-class-perl
```

## Supported Lisp Implementations
Many CwC components are written in Lisp. We only officially support
SBCL, though we have made some effort to also support CCL.

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

