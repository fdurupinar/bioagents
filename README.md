# Communicating with Computers Integration
This is top-level projects organizes CwC integration and demo efforts.

# Prerequisites

## Operating System
This integrated environment has been tested on Mac OSX and Debian -- a
Jenkins environment at SIFT automatically tests the system each time a
change is made to a relevant repository. Other OSes may work, but are
not officially supported.

## Lisp
Many CwC components are written in Lisp. We only officially support
SBCL, though we have made some effort to also support CCL.

## Perl
This project uses several Perl scripts to facilitate tasks (e.g.,
updating the environment, running tests). These scripts require
several libraries. Before you begin, (and later if any of the Perl
scripts fail with an indication that they cannot find a library),
look at the [Perl Libraries](#perl-libraries) section below for
guidance on how to install any libraries you don't already have.

## Python
The HMS Bioagents software is written in Python and relies on numerous
Python libraries. Again, before you begin (and later if the Bioagents
fail to find a library), see the [Python Libraries](python-libraries)
section below.

## BioNetGen
The HMS Bioagents software (the MRA in particular) requires [BioNetGen](http://www.bionetgen.org/index.php/Main_Page)
to generate model diagrams.

I downloaded the command line binary distribution from:
http://www.bionetgen.org/index.php/BioNetGen_Distributions

It looks like the MRA expects this to reside in
```/usr/local/share/BioNetGen```, so I uncompressed the archive there and
renamed it, removing the version number from the directory name.

# Getting Started
1. Clone the cwc-integ project.
    ```
git clone https://gitlab.com/cwc/cwc-integ.git
```

    (If you want to use SSH with a key instead of HTTPS with a password, you
    can replace ```https://gitlab.com/``` with ```git@gitlab.com:``` after
    setting up your key on GitLab, as described in the [Git Tips](#git-tips)
    section.)

2. Download or check out the SHOP2 HTN planner.

    The SHOP2 planner is maintained in an svn repo at SIFT. If you
    have credentials for this repo, you can check it out as in:
    ```
cd cwc-integ
svn co https://svn.sift.net:3333/svn/shop2/shop/trunk/shop2
```

    Otherwise, you can download the stable release from SourceForge --
    https://sourceforge.net/projects/shop/. Uncompress the release
    in ```cwc-integ/``` and rename it ```cwc-integ/shop2/```, removing
    the version number from the directory name (as with BioNetGen).

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
- ```IPC::Run``` / ```libipc-run-perl```
- ```IO::Pty``` / ```libio-pty-perl```

# Python Libraries
The HMS bioagents are implemented in Python. They require Python 2.7.x
and some libraries. As with the Perl libraries, there are potentially
multiple ways to satisfy these dependencies.

On Mac OSX, I used pip to install them:
```
pip install sympy
```

On Debian, I installed them via the package manager, as in:
```
aptitude install python-sympy
```

Note that if you have multiple versions of python installed, it may
help to use
[virtualenv](http://docs.python-guide.org/en/latest/dev/virtualenvs/)
to set up a local python environment to install these libraries in.
For example, I (Will) got an error message complaining about
"numpy < 1.7.0" when ```pip show numpy``` said I had version 1.11.0,
and using virtualenv fixed it.

There may be other modules, but you definitely need to have:
- ```sympy``` / ```python-sympy```
- ```rdflib``` / ```python-rdflib```
- ```pygraphviz``` / ```python-pygraphviz```
 - ```pygraphviz``` requires ```graphviz``` to be installed in a way that it
   can be found using ```pkg-config```. On the Mac, you can install it via
   MacPorts using ```sudo port install graphviz``` (you may also need to
   install ```pkgconfig``` itself this way). Or you can install
   ```Graphviz.app```, which installs to ```/usr/local/```, so if you do it
   this way you may also need to add ```/usr/local/lib/pkgconfig``` to your
   ```PKG_CONFIG_PATH``` environment variable.
- ```matplotlib``` / ```python-matplotlib```
- ```functools32```
- ```suds``` / ```python-suds```
- ```scipy``` / ```python-scipy```
- ```pandas``` / ```pythons-pandas```
- ```indra``` / (no Debian package?)

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

Alternatively, you can use SSH keys for GitLab repos, avoiding
passwords altogether. Just follow
[GitLab's SSH key configuration instructions](https://gitlab.com/help/ssh/README),
and update the `remote_url` in your `etc/local-conf.json`, replacing
`https://gitlab.com/` with `git@gitlab.com:`. For example:
```
{
    "git_repos": [
        { "name": "spire",
          "remote_url": "git@gitlab.com:sift/spire.git"},
        { "name": "clic",
          "remote_url": "git@gitlab.com:sift/clic.git"}
    ]
}
```
