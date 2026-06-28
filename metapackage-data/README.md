# Notes on metapackage dependencies

Before adding notes to this document, consider if they belong on the Wiki
instead. This file should be used for anything where a code comment would be
used in `core-control-file` (which does not support comments).

# virtualbox-guest-additions-iso dependency mess

Previously, we used `virtualbox-guest-x11` and `virtualbox-guest-utils` to
provide Guest Additions in Kicksecure. These packages worked well until the
release of VirtualBox 7.2.8, which provided (mostly) functional clipboard
sharing under Wayland. Clipboard sharing required newer Guest Additions than
are present in the Debian Trixie stable repositories. The easiest solution to
this would have been to upgrade to VirtualBox Guest Additions packages from
Debian Fasttrack, but at the time of writing the newest VirtualBox packages
(including Guest Additions) provided by Fasttrack are on version 7.2.6. Prior
experience has shown that Fasttrack does not move fast enough for our needs by
themselves, and is resistant (though not hostile) to contributions from the
outside, so we cannot depend on them to provide new enough packages in a
reasonable time frame. For this reason, we have chosen to get our Guest
Additions packages from the Guest Additions ISO provided by Oracle.

There are a couple secure ways of getting this ISO:

* From the `virtualbox-guest-additions-iso` packages provided by Debian
  Trixie, Sid, or Fasttrack. Trixie's package is too old, as is Fasttrack's.
  Sid's is new enough, but it is still somewhat outdated, and it may require
  significant effort to help Debian with maintaining it in the event we need
  it updated quicker than Debian would do otherwise.
  * It should be noted this is not the most secure method of getting the ISO;
    while Debian's apt packages are obviously signed, the script used by
    Debian to download the ISO for packaging fetches the ISO over HTTPS and
    assumes it is intact and not tampered with. Beyond that, this package
    `Recommends: virtualbox` (a non-Oracle build that will get pulled from
    Debian Fasttrack by default), which will get pulled in by a
    `sudo apt full-upgrade` by default; this causes the same problem as using
    a `virtualbox-*` package, as described below.
* From the `virtualbox-*` packages from Oracle. These packages are guaranteed
  to be up-to-date, and are fully signed (ISO included), but they include all
  of VirtualBox. We can't install all of VirtualBox inside users' VirtualBox
  VMs or we will confuse people.

For this reason, we have chosen to go with a hybrid of the two options;
download `virtualbox-*` packages from Oracle, extract the ISO from these
packages, then package it as a `virtualbox-guest-additions-iso` package with
a version number higher than Debian's package of the same name. This package
is depended on by `dist-vm-gui-all` and `dist-baremetal-gui-all` to install it
on end-user systems, and these packages also
`Breaks/Replaces: virtualbox-guest-x11, virtualbox-guest-utils` to ensure a
smooth transition. We then use `vbox-guest-installer` (a script shipped with
`vm-config-dist`) to install Guest Additions from this ISO into the VM
automatically.

This works as long as the user doesn't want a `virtualbox-*` package
installed, but what if they do want this? Oracle's `virtualbox-*` packages
`Conflicts: virtualbox-guest-additions-iso`, meaning that installing
VirtualBox will uninstall important metapackages. We install
`virtualbox-guest-additions-iso` by default even on baremetal for multiple
reasons (need Guest Additions on the ISO, physical-to-virtual migration should
be as easy as possible), so users will probably want to install VirtualBox on
a system with `virtualbox-guest-additions-iso` currently installed. We do not
use `Recommends` in any of our packages so that we can use
`--no-install-recommends` liberally and avoid VM bloat, we have to use
`Depends`. We can't use a `dummy-dependency` package to get around this
situation, because that package would have to
`Provides: virtualbox-guest-additions-iso`, thus causing VirtualBox to
conflict with even the `dummy-dependency` package. The only remaining way to
square the circle is to use a multiple-choice dependency. Oracle's VirtualBox
packages `Provides: virtualbox`, so we could theoretically use
`virtualbox-guest-additions-iso | virtualbox` to resolve the issue.

This however presents another issue; when presented with a multiple-choice
dependency, apt will sometimes pick a dependency other than the left-most one
in the list, even if the left-most dependency would work without causing any
dependency issues. This would be particularly disastrous if we used
`Depends: virtualbox-guest-additions-iso | virtualbox`, because Oracle's
VirtualBox packages are not named `virtualbox`, they are named `virtualbox-*`.
`virtualbox` is the name of the non-Oracle build of VirtualBox in Debian
Fasttrack (which is enabled by default), and that packages does *not* include
a Guest Additions ISO! If apt decided to install `virtualbox` instead of
`virtualbox-guest-additions-iso`, this would not only provide a full
VirtualBox installation where it isn't wanted, it would also fail to provide
the one file we're trying to ship to users! To work around this, we must
depend on Oracle's VirtualBox packages specifically, so that if apt does
decide to install the wrong dependency, at least the user gets working Guest
Additions.

Here we run into another issue; Oracle does not provide any one VirtualBox
metapackage pointing to the latest stable version of VirtualBox. They instead
offer one VirtualBox package per minor version branch, i.e. `virtualbox-7.1`,
`virtualbox-7.2`, etc. We can omit VirtualBox versions that are lower than the
version of VirtualBox our `virtualbox-guest-additions-iso` package comes from,
but users should be allowed to install newer versions at will in the event we
forget to version-dump this dependency in the future. Therefore, we need to
depend on any one of multiple branches of VirtualBox, including branches that
don't exist yet but that are likely to exist in the future. According to
https://www.virtualbox.org/wiki/Changelog-7.2, VirtualBox hasn't had a minor
version greater than `.3` for any major version of VirtualBox since 2015, so
we are likely safe if we depend on every (possibly) supported VirtualBox
branch from 7.2 to 7.4, and then also from 8.0 to 8.4 (despite knowing that
7.4 and 8.4 will most likely never exist).


In the end, this means we have a dependency that looks like this any time we
want to pull in the Guest Additions ISO:
`virtualbox-guest-additions-iso | virtualbox-7.2 | virtualbox-7.3 | virtualbox-7.4 | virtualbox-8.0 | virtualbox-8.1 | virtualbox-8.2 | virtualbox-8.3 | virtualbox-8.4`.
This is a horrible hack, but it is the only solution that solves all issues
so far.
