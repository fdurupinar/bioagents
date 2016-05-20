# Communicating with Computers Integration

This is top-level projects organizes CwC integration and demo efforts.

# Getting Started

```
git clone https://gitlab.com/cwc/cwc-integ.git
cd cwc-integ
scripts/verify-env.perl
scripts/run-test.perl :spire
scripts/run-test.perl :spire/test-sparser
```

# Requirements

Many CwC components are written in Lisp. We have made efforts to be
compatible with both SBCL and CCL, but ultimately we only official
support SBCL.

# Tips

If git repeatedly asks for credentials to access GitLab repos, you may
want to add the following to your ```~/.gitconfig``` file.
```
[credential]
    helper = osxkeychain
```
