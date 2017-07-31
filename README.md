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
[SBCL](http://www.sbcl.org) (1.3.1 or later; some code is known not to 
work in 1.2.11), though we have made some effort to also support CCL.
You will need to make sure your lisp has multithreading support; for
example, on the Mac, an easy way to get this is through ​
[MacPorts](http://www.macports.org/), using:
```
sudo port install sbcl +threads
```
or [Homebrew](http://brew.sh/)
```
brew install sbcl
```
## Perl
This project uses several Perl scripts to facilitate tasks (e.g.,
updating the environment, running tests). These scripts require
several libraries. Before you begin (and later if any of the Perl
scripts fail with an indication that they cannot find a library),
look at the [Perl Libraries](#perl-libraries) section below for
guidance on how to install any libraries you don't already have.

## Python
The HMS Bioagents software is written in Python (currently only Python 2
is supported) and relies on numerous
Python libraries. Again, before you begin (and later if the Bioagents
fail to find a library), see the [Python Libraries](#python-libraries)
section below.

## NodeJS
This project uses NodeJS to host a webserver with pages for
interacting with the integrated system. In addition, there is an
optional web interface (SBGNViz) for the biocuration domain which also
requires NodeJS. 

The verify-env script (described below) runs ```npm install``` in the
directories which require it. There are multiple failure modes
that one needs to be aware of, some described in this section, others
in the [SBGNViz section](#sbgnviz) below for some hints.

### NodeJS on Linux
Many Linux distributions install old versions of NodeJS
(e.g. 0.12) by default when doing `apt-get install nodejs`. To get NodeJS
version 8, follow instructions on this page:
https://nodejs.org/en/download/package-manager/
For instance, on Debian, installing NodeJS 8 can be done by
```
curl -sL https://deb.nodesource.com/setup_8.x | sudo -E bash -
sudo apt-get install nodejs
```
This also makes `npm` available which can be used to install NodeJS packages.

It appears that any globally installed `npm` packages can interfere with
the locally installed ones within cwc-integ. Therefore a full cleanup of
globally installed packages (i.e. `npm -g rm <package name>`) and
removal of local packages (i.e. `rm -r plexus/node_modules`, and
same for the `spire/plexus/node_modules` and `clic/plexus/node_modules`
folders) is needed before running `verify-env.perl`.

### NodeJS on Mac

To install NodeJS on Mac, use Homebrew of Macports, that is:
```
brew install node
```
or
```
sudo port install nodejs8
sudo port install npm4
```

## TRIPS prerequisites

TRIPS requires [WordNet](http://wordnet.princeton.edu/),
[CoreNLP](http://stanfordnlp.github.io/CoreNLP/) (v3.5.2. or later), the 
[Enju parser](http://kmcs.nii.ac.jp/enju/downloads?lang=en), and the
[MESH Supplementary Concept Records (SCR) in ASCII format](https://www.nlm.nih.gov/mesh/download_mesh.html). 
**You should follow the instructions**
[here](http://trips.ihmc.us/trac/drum/wiki/TripsDrumSystemInstallation#Prerequisites)
on how and where to install these files. More biomedical resources will be downloaded during
the first make (which may take a rather long time). Generally, after any
update of the TRIPS environment (prerequisites, lisp implementation or version
thereof, etc.), you will want to make clean and
[re-configure](http://trips.ihmc.us/trac/drum/wiki/TripsDrumSystemInstallation#Configuringmakinginstalling)
manually. 

### TRIPS: Stanford CoreNLP
On some Linux platforms `xsltproc` needs to be installed as,
for instance, `sudo apt-get install xsltproc` to run Stanford CoreNLP.

### TRIPS: Enju
Enju does not provide executables anymore so you need to get a copy
of a working enju package from
- Enju 2.4.2 for Debian: https://www.dropbox.com/s/25533hj57p7wcdz/enju-2.4.2-debian.tar.gz?dl=0
- Enju 2.4.2 for Mac: https://www.dropbox.com/s/ne6gueb10zu4x8e/enju-2.4.2-Mac.zip?dl=0

On some Linux
platforms `libc6-i386`, `lib32z1` and `lib32stdc++6` need to be installed to
successfully run enju.

### TRIPS: National File
Some users have reported a change in the website to download the NationalFile.
A working copy can be downloaded here:
- National File: https://www.dropbox.com/s/ryy30bwbtobc7un/NationalFile_20150401.zip?dl=0

### TRIPS: broken resource files
Some resource files that TRIPS downloads during installation can be broken
from time to time. In this case you need to obtain a copy from someone whith a
working installation. Currently the following files are broken and can be
obtained from the links below:
- BrendaTissueOBO: https://www.dropbox.com/s/2o6261e71i6uqqo/BrendaTissueOBO?dl=0
- cv_family.txt: https://www.dropbox.com/s/uydmjxc3w4i9si7/cv_family.txt?dl=0


## BioNetGen
The HMS Bioagents (the MRA in particular) require [BioNetGen](http://www.bionetgen.org/index.php/Main_Page) to generate model diagrams.

The binary distribution can be downloaded from: http://www.bionetgen.org/index.php/BioNetGen_Distributions

The MRA expects this to be in
```/usr/local/share/BioNetGen```, so the downloaded archive needs to be extracted and
renamed, removing the version number from the directory name.

## SBGNViz (optional/experimental)
The biocuration system can optionally be launched with the SBGNViz 
collaborative environment. **Installation instructions are not finalized
and the connection with Bob is under active development and can change,
requiring re-configuration.
Please keep this in mind before setting up SBGNViz with Bob.**

To run with the SBGNViz front-end, launch the system as 
`perl scripts/run-cwc.perl bio -sbgnviz`.
SBGNViz is implemented in JavaScript, and depends on `mongodb`.
On Mac, MongoDB can be installed as
```
brew install mongodb
```
or
```
sudo port install mongodb
```

MongoDB needs to be running as a service when launching the system. On Mac there
are multiple ways to run MongoDB. 
Either create an empty db and run mongod as:
```
cd Sbgnviz-Collaborative-Editor
mkdir -p data/db
mongod --dbpath data/db/
```
alternatively you can
```
brew tap homebrew/services
brew services start mongodb
```
On Linux on can start it as a service as
```
sudo service mongod start
```

For detailed SBGNViz instructions and instructions for other platforms read
[this](https://github.com/fdurupinar/Sbgnviz-Collaborative-Editor).

To run SBGNViz, `npm` needs to install the required node modules in
both the main SBGNViz directory and the SBGNViz/public directory. The
public directory requires the ```libxmljs``` library. Installing
```libxmljs``` does not always work perfectly. Here are some specific
things to try if you encounter problems:

1. Make sure that the ```python``` in your path is version 2.7.

2. Make sure that the ```libtool``` in your path is
   ```/usr/local/bin``` -- the ```libtool``` installed by MacPorts (in
   ```/opt/local/libexec/gnubin/libtool```) does __not__ work.

3. If you have encountered problems and are trying again, be sure to
   remove the ```public/node_modules``` and maybe also run ```npm
   rebuild``` in the ```public``` directory.

## Kappa (optional)
When using the system with the SBGNViz environment, visualizations using the
Kappa Static Analyzer (KaSa) are generated. To make these available, Kappa
needs to be installed locally. [You need to have opam installed on your system 
first.](https://opam.ocaml.org/doc/Install.html)


Then follow these steps to install Kappa:
```
opam init -a git://github.com/ocaml/opam-repository && eval $(opam config env)
opam install -y conf-which base-bytes
opam install -y ocamlbuild yojson
git clone https://github.com/Kappa-Dev/KaSim.git
cd KaSim
make all
export KAPPAPATH=`pwd`
```

# Getting Started
1. Clone the cwc-integ project.
    ```
git clone https://gitlab.com/cwc/cwc-integ.git
```

    (If you want to use SSH with a key instead of HTTPS with a password, you
    can replace ```https://gitlab.com/``` with ```git@gitlab.com:``` after
    setting up your key on GitLab, as described in the [Git Tips](#git-tips)
    section.)

2. [Optional] Create an ```etc/local-conf.json``` file with custom
   settings. See [below](#custom-environment-setup) for details.

3. Verify that your environment is set up properly. Fix it if
   necessary.

    The first time you run this, the script will clone a bunch of git
    repos and check out some svn repos. After that, running this
    script should only update the local copy when remote changes are
    found.
    ```
cd cwc-integ
scripts/verify-env.perl --fix
```

4. You may need to configure (or reconfigure) one or both of the TRIPS
   systems. In case, you can execute the following to generate the
   appropriate configure commands for CABOT and BOB, respectively:
   ```
scripts/verify-trips-build.perl trips-cabot
scripts/verify-trips-build.perl trips-bob
```
These configure commands will assume the location of your geonames,
enju, WordNet, and other linguistic resources, and you must make
   corrections as necessary; otherwise, TRIPS will not build or
   execute reliably. If you want to force a reconfigure one of the above systems, delete
   the ```trips/<system>/src/Makefile``` and then run the above perl
   script(s).

5. Run the tests to verify that everything is working. The Jenkins
   script always runs ```verify-env.perl --fix```, so the tests should
   always run against an up-to-date environment.
    ```
cd cwc-integ
scripts/jenkins.perl
```

# Running the Integrated System
To run the integrated system, use the ```scripts/run-cwc.perl```
script. This script starts TRIPS, bioagents (if necessary), and
SPG. Pass an argument to the script to tell it what domain to
start. The script recognizes: bw, blocksworld, bio, and biocuration.

So, the simplest way to start the system is:
```
scripts/run-cwc.perl bw
```
or
```
scripts/run-cwc.perl bio
```

See the top of the script for details on additional arguments. The
most useful arguments are:
- ```-n``` or ```--nouser``` -- when this flag is pass, the script
  adds the ```nouser``` argument when running TRIPS. This prevents the
  TRIPS UI components from starting.
- ```-s``` or ```--show-browser``` -- when this flag is used, the
  script watches for the SPG to finish starting and then opens a web
  browser to the web page for the demo.

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
- ```DBI```
- ```Set::Scalar```
- ```File::Slurp```
- ```XML::LibXML``` (needed by TRIPS EKBAgent)
- ```List::Util``` (needed by TRIPS EKBAgent)
- ```Test::Deep::NoTest``` (needed by TRIPS EKBAgent)
- ```Algorithm::Diff``` (needed by TRIPS EKBAgent)

# Python Libraries
The HMS bioagents are implemented in Python. They require Python 2.7.x
and additional packages. If you installed Python via MacPorts, you can
set your default Python executable as in:
```
sudo port select python python27
```

As with the Perl libraries, there are potentially multiple 
ways to satisfy these dependencies.

The easiest way to install packages is with `pip` such as:
```
pip install sympy numpy scipy
```
As above, you can install multiple packages with a single command by passing
their names to pip separated by spaces.

Alternatively, there is a `cwc-integ/python_requirements.txt` file, which 
you can use to install all python packages with a single command as:
```
pip install -r python_requirements.txt
```

On Debian, if a system installation is preferred, one can install these dependencies
using the package manager, as in:
```
aptitude install python-sympy
```

Note that if you have multiple versions of python installed, it may
help to use
[virtualenv](http://docs.python-guide.org/en/latest/dev/virtualenvs/)
to set up a local python environment to install these libraries in.
Virtualenv allows the creation of project-specific python environments with
different versions of packages (and potentially different version of Python)
installed in each environment. Also, keep in mind that the PYTHONPATH environment
variable, if set, might result in unexpected versions of python
packages to be loaded.

There may be other modules, but you definitely need to have:
- ```sympy``` / ```python-sympy```
- ```scipy``` / ```python-scipy```
- ```numpy``` / ```python-numpy```
- ```rdflib``` / ```python-rdflib```
- ```pygraphviz``` / ```python-pygraphviz```
 - ```pygraphviz``` requires ```graphviz``` to be installed in a way that it
   can be found using ```pkg-config```. On the Mac, you can install it via
   using ```sudo port install graphviz``` (you may also need to
   install ```pkgconfig``` itself this way) or ```brew install graphviz```. 
    The solution to a commonly encountered problem when installing `pygraphviz` on Mac using `brew` 
is [here](http://www.alexandrejoseph.com/blog/2016-02-10-install-pygraphviz-mac-osx.html).
- ```matplotlib``` / ```python-matplotlib```
- ```suds``` / ```python-suds```
- ```pandas``` / ```python-pandas```
- ```requests```
- ```lxml```
- ```jsonpickle``` / ```python-jsonpickle```
- ```future```
- ```functools32```
- ```ndex```
- ```networkx```
- ```enum34```
- ```socketIO-client``` (optional, for SBGNViz integration)

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

If you are only working with one version of TRIPS and would like to
avoid cloning, updating, and building the other versions, you can add
something like this to ```etc/local-conf.json```.
```
{
    "git_repos": [
        // Skip unused versions of TRIPS.
        { "name": "trips-bob",
          "skip": true },
        { "name": "trips-cabot",
          "skip": true }
    ]
}
```

# Collaboration and Documents
There is a CwC Biocuration project at Basecamp. Use this for public
discussions and document sharing.
https://basecamp.com/2716585/projects/10031598

Ben wrote up a Google doc with the [bioagent tasking specification](https://docs.google.com/document/d/14DVvzBxKDew5fA241Cn49ThOIq3dgP12oVNPvMOcwW4/edit).

Ben also wrote up a Google doc with design/plan for [talking about model properties](https://docs.google.com/document/d/1gPIh6xZwPd9vucYbTmGltTWUNQGTuNpCFOlvvnawmuc/edit).

IHMC has also created some design/API documents relevant to this
effort.
- [CwC: Inter-agent Communicative Acts](https://docs.google.com/document/d/1pz5QT2VW4YPyY7VsP1kibhlUTUZE8f9ZpQXEvDxGrg0/edit?usp=sharing)
- [Goal and Status API](https://docs.google.com/document/d/16SADT4vGcCryB_PsoQHuDs5V9RlR2F63ijNFRmFW0vw/edit?usp=sharing)
- [Todo List](https://docs.google.com/document/d/1ax1_3Eaes7xktltLiWbyXnTJj1sUf0lEaYqhVuSqf-o/edit?usp=sharing)

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

## ```scripts/run-cwc.perl```
Runs the integrated system. Run as:
```
scripts/run-cwc.perl bw
scripts/run-cwc.perl bio
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
