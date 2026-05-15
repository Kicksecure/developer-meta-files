#!/bin/bash

## Copyright (C) 2026 - 2026 ENCRYPTED SUPPORT LLC <adrelanos@whonix.org>
## See the file COPYING for copying conditions.

## AI-Assisted

## CI helper: install genmkfile from its upstream git repository
## into the system. genmkfile then becomes available on PATH so
## subsequent CI steps can use `genmkfile install` to install
## helper-scripts and the caller repo itself.
##
## Context-aware sudo: works both in a root container
## (debian:trixie etc., no sudo wrapper) and on a non-root host
## runner (ubuntu-latest, sudo NOPASSWD).
##
## Org resolution: defaults to Kicksecure (the canonical upstream).
## Override with GENMKFILE_OWNER env var when running from a
## mirror org (e.g. org-ai-assisted) that hosts its own fork.

set -o errexit
set -o nounset
set -o pipefail
set -o errtrace
shopt -s inherit_errexit
shopt -s shift_verbose

if [ "${CI:-}" != "true" ]; then
   printf '%s\n' \
      'error: this script must run with CI=true (GitHub Actions or equivalent).' >&2
   exit 1
fi

## Trailing '--' in the array terminates sudo's option parsing -
## defense in depth so a future prepended argument cannot smuggle
## a sudo flag.
sudo_prefix=()
if [ "$(id -u)" -ne 0 ]; then
   sudo_prefix=(sudo --non-interactive --)
fi

readonly sudo_prefix
readonly clone_dir='/tmp/genmkfile-install'
readonly upstream_owner="${GENMKFILE_OWNER:-Kicksecure}"
readonly upstream_url="https://github.com/${upstream_owner}/genmkfile.git"

git clone --depth=1 --no-tags --branch=master -- "${upstream_url}" "${clone_dir}"
cd -- "${clone_dir}"
GENMKFILE_DEBUG=1 "${sudo_prefix[@]}" ./usr/bin/genmkfile deb-all-dep
GENMKFILE_DEBUG=1 "${sudo_prefix[@]}" ./usr/bin/genmkfile install
