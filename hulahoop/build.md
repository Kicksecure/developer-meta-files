# Build, Compress and Sign #

Setup build machine according to pages above then run the following commands to create builds:

```
dist_build_redistributable=true ./derivative-maker --target qcow2 --flavor whonix-gateway-lxqt
```

Optionally add `--connection onion` to force fetching packages from `.onion` servers.

For Kicksecure replace `whonix-gateway-lxqt` with: `kicksecure-lxqt` / `kicksecure-cli`

# Upload Command

Upload to whonix.org

* (server fingerprint: `SHA256:tsvKWEuUwbP0vx+vrePlMqbC4qUXn5fscrm/lZLhVrE`)
* (server folder: `/home/hulahoop/libvirt/version-number/vm-name....`):

Upload to kicksecure.com

* (server fingerprint: `256 SHA256:NuvDfRYfQiX4MeQZbENPbaenSKatJ2Lwrrmi78jSZtg root@Debian-105-bookworm-64-minimal (ED25519)`)
* (server folder: `/home/hulahoop/libvirt/version-number/vm-name....`):

```
ssh_uploader_account="hulahoop" dm-upload-images --target qcow2 --flavor kicksecure-lxqt
```

```
ssh_uploader_account="hulahoop" dm-upload-images --target qcow2 --flavor whonix-workstation-lxqt
```

Note: No need to repeat for `--whonix-gateway-lxqt` because of unified libvirt images.

# Tor Browser Version Setting #

Tor Browser Version: If needed in the future, a builder could set `tbb_version="8.5.5" `, i.e. instructing `tb-updater` to download Tor Browser version `8.5.5`. This can be useful because, for example `tb-updater` for the Whonix `15.0.0.4.9` build pointed hardcoded Tor Browser version `8.5.4` which was no longer available for download at time of the build which resulted in the build failing.

Example usage...

Note: The version number `8.5.5` needs to be updated if needed. Check https://aus1.torproject.org/torbrowser/update_3/release/downloads.json for latest stable Tor Browser version.

```
tbb_version="8.5.5" "$HOME/derivative-maker/derivative-maker" --target qcow2 --flavor whonix-workstation-lxqt
```
