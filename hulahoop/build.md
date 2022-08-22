# step based build system #

You don't need to use ~/derivative-maker/derivative-maker at all. Each step can be done separately. https://www.whonix.org/wiki/Dev/Source_Code_Intro#Introduction would be unworkable without that feature.
These are the build-steps:

```
ls -la ~/derivative-maker/build-steps.d/
```

# build #

Setup build machine according to pages above then run the following commands to create builds:

```
./derivative-maker --flavor whonix-gateway-xfce --build --arch amd64 --repo true --target qcow2
```

```
SKIP_SCRIPTS+=" 1100_prepare-build-machine 1200_create-debian-packages " ./derivative-maker --flavor whonix-workstation-xfce --build --arch amd64 --repo true --target qcow2
```

Optionally add `--connection onion` to force fetching packages from Onion servers.

For Kicksecure replace `whonix-gateway-xfce` with: `kicksecure-xfce` / `kicksecure-cli`

# Sign and Compress #

Run command below to sign and compress. Btw Gateway prepare release command does nothing as expected and the Workstation prepare release command will do everything (both gw and ws):

```
dm-prepare-release --build --target qcow2 --flavor whonix-workstation-xfce
```

# Upload to whonix.org #

* (server fingerprint: `SHA256:tsvKWEuUwbP0vx+vrePlMqbC4qUXn5fscrm/lZLhVrE`)
* (server folder: `/home/hulahoop/libvirt/version-number/vm-name....`):

```
dm-upload-images --build --target qcow2 --flavor whonix-workstation-xfce
```

# Upload to kicksecure.com #

* (server fingerprint: `256 SHA256:NuvDfRYfQiX4MeQZbENPbaenSKatJ2Lwrrmi78jSZtg root@Debian-105-buster-64-minimal (ED25519)`)
* (server folder: `/home/hulahoop/libvirt/version-number/vm-name....`):

```
dm-upload-images --build --target qcow2 --flavor kicksecure-xfce
```

# Upload to sf.net #

Deprecated!

Don't run this script as root. Type sf.net password when prompted:

```
export server="hulahoop,whonix-kvm@frs.sourceforge.net:/home/frs/project/whonix-kvm/libvirt"
```

`export server` is also deprecated.

# ssh keys #

Creating SSH server pub key via cli (can be also done manually by saving th contents in a .pub file). May need to delete `~/.ssh/known_hosts` if previous attempts failed. This step is not necessary because the keys are saved in the backed up `.ssh`:

```
ssh-keygen -lf ssh_host_ed25519_key.pub
```

```
256 SHA256:tsvKWEuUwbP0vx+vrePlMqbC4qUXn5fscrm/lZLhVrE
root@Debian-98-stretch-64-minimal (ED25519)
```

# SKIP_SCRIPTS #

```
SKIP_SCRIPTS+=" ... "
```

```
export SKIP_SCRIPTS
```

# Tor Browser Version Setting #

Tor Browser Version: If needed in the future, a builder could set `tbb_version="8.5.5" `, i.e. instructing `tb-updater` to download Tor Browser version `8.5.5`. This can be useful because, for example `tb-updater` for the Whonix `15.0.0.4.9` build pointed a hardcoded Tor Browser version `8.5.4` which was no longer available for download at time of the build which resulted in the build failing.

Example usage...

Note: The version number `8.5.5` needs to be updated if needed. Check https://aus1.torproject.org/torbrowser/update_3/release/downloads.json for latest stable Tor Browser version.


```
tbb_version="8.5.5" ~/derivative-maker/derivative-maker --flavor whonix-workstation-xfce --target qcow2 --build
```
