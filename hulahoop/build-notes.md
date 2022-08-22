# step based build system #

You don't need to use ~/derivative-maker/derivative-maker at all. Each step can be done separately. https://www.whonix.org/wiki/Dev/Source_Code_Intro#Introduction would be unworkable without that feature.
These are the build-steps:

```
ls -la ~/derivative-maker/build-steps.d/
```

# SKIP_SCRIPTS #

```
SKIP_SCRIPTS+=" ... "
```

```
export SKIP_SCRIPTS
```

```
SKIP_SCRIPTS+=" 1100_prepare-build-machine 1200_create-debian-packages " ./derivative-maker --flavor whonix-workstation-xfce --build --arch amd64 --repo true --target qcow2
```

# Upload to sf.net #

Deprecated!

Don't run this script as root. Type sf.net password when prompted:

```
export server="hulahoop,whonix-kvm@frs.sourceforge.net:/home/frs/project/whonix-kvm/libvirt"
```

`export server` is also deprecated.
