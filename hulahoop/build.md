# Build #

Setup build machine according to pages above then run the following commands to create builds:

```
./derivative-maker --target qcow2 --flavor whonix-gateway-xfce --repo true --tb closed
```

Optionally add `--connection onion` to force fetching packages from `.onion` servers.

For Kicksecure replace `whonix-gateway-xfce` with: `kicksecure-xfce` / `kicksecure-cli`

# Sign and Compress #

Run command below to sign and compress.

```
dm-prepare-release --target qcow2 --flavor kicksecure-xfce
```

```
dm-prepare-release --target qcow2 --flavor whonix-workstation-xfce
```

Note: No need to repeat for `--whonix-gateway-xfce` because of unified libvirt images.

# Upload Command

Upload to whonix.org

* (server fingerprint: `SHA256:tsvKWEuUwbP0vx+vrePlMqbC4qUXn5fscrm/lZLhVrE`)
* (server folder: `/home/hulahoop/libvirt/version-number/vm-name....`):

Upload to kicksecure.com

* (server fingerprint: `256 SHA256:NuvDfRYfQiX4MeQZbENPbaenSKatJ2Lwrrmi78jSZtg root@Debian-105-bookworm-64-minimal (ED25519)`)
* (server folder: `/home/hulahoop/libvirt/version-number/vm-name....`):

```
dm-upload-images --target qcow2 --flavor kicksecure-xfce
```

```
dm-upload-images --target qcow2 --flavor whonix-workstation-xfce
```

Note: No need to repeat for `--whonix-gateway-xfce` because of unified libvirt images.

# Tor Browser Version Setting #

Tor Browser Version: If needed in the future, a builder could set `tbb_version="8.5.5" `, i.e. instructing `tb-updater` to download Tor Browser version `8.5.5`. This can be useful because, for example `tb-updater` for the Whonix `15.0.0.4.9` build pointed hardcoded Tor Browser version `8.5.4` which was no longer available for download at time of the build which resulted in the build failing.

Example usage...

Note: The version number `8.5.5` needs to be updated if needed. Check https://aus1.torproject.org/torbrowser/update_3/release/downloads.json for latest stable Tor Browser version.

```
tbb_version="8.5.5" ~/derivative-maker/derivative-maker --target qcow2 --flavor whonix-workstation-xfce
```
