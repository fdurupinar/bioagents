# Communicating with Computers Integration

This is top-level projects organizes CwC integration and demo efforts.

# Getting Started

```
git clone https://gitlab.com/cwc/cwc-integ.git
cd cwc-integ
scripts/verify-env.perl --fix
scripts/run-test.perl :spire
scripts/run-test.perl :spire/test-sparser
```

# Requirements

Many CwC components are written in Lisp. We have made efforts to be
compatible with both SBCL and CCL, but ultimately we only official
support SBCL.

## Perl

The Perl scripts in this project have several external
dependencies. These must be manually installed on each developer
machine. We have installed these with invocations like:

```
sudo perl -MCPAN -e shell
CPAN> install Path::Class
```

and

```
aptitude install libpath-class-perl
```

Among the required Perl modules are:
- Path::Class / libpath-class-perl


# Tips

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

