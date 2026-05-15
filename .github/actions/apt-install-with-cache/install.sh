#!/bin/bash

## Copyright (C) 2026 - 2026 ENCRYPTED SUPPORT LLC <adrelanos@whonix.org>
## See the file COPYING for copying conditions.

## AI-Assisted

## Wrapper around `apt-get install` that pairs with an
## actions/cache step caching ~/.apt-deb-cache. Seeds apt's archive
## with previously-cached .debs before install (so apt-get install
## reuses them instead of re-downloading), then snapshots any
## newly-downloaded .debs back into the cache for the next run.
##
## Why a runner-owned sidecar (not caching /var/cache/apt/archives
## directly):
##
## /var/cache/apt/archives is root:root 0755 with an _apt:root 0700
## 'partial/' subdirectory. apt deliberately drops privileges
## during the download phase; partial/ holds unverified bytes that
## the _apt system user owns mode 0700. actions/cache runs tar as
## the unprivileged runner user, so caching the system directory
## directly leaves only two doors: (a) `sudo chown -R` clobbers
## apt's permission model, and apt recreates partial/ 0700 every
## install anyway - a perpetual fight; (b) `sudo chmod o+w` drops
## a world-writable bit on a system directory. Neither is
## acceptable. A runner-owned sidecar lets actions/cache tar/untar
## with zero interaction with apt's permissions.
##
## Usage:
##   apt-install-with-cache.sh PACKAGE [PACKAGE ...]
##
## Paired workflow steps (caller's responsibility):
##   - name: Cache apt downloads
##     uses: actions/cache@<sha>
##     with:
##       path: ~/.apt-deb-cache
##       key: ${{ runner.os }}-apt-<tool>-${{ hashFiles('<workflow>') }}
##   - name: Install
##     run: .github/dmf/ci/apt-install-with-cache.sh PACKAGE [...]
##
## CI guard mirrors ci/coverity-check-secrets.sh - this script has
## no sensible local invocation (no developer machine should be
## sudo-copying into /var/cache/apt/archives); ALLOW_LOCAL=true
## overrides for the rare-on-purpose case.

set -o errexit
set -o nounset
set -o pipefail
set -o errtrace
shopt -s inherit_errexit
shopt -s shift_verbose
shopt -s nullglob

if [ "${CI:-}" != "true" ] && [ "${ALLOW_LOCAL:-}" != "true" ]; then
   printf '%s\n' "${BASH_SOURCE[0]}: refusing to run outside CI (CI != 'true'). Set ALLOW_LOCAL=true to override." >&2
   exit 1
fi

if [ "$#" -lt 1 ]; then
   printf '%s\n' "usage: ${BASH_SOURCE[0]} PACKAGE [PACKAGE ...]" >&2
   exit 64
fi

cache_dir="${HOME}/.apt-deb-cache"
mkdir --parents -- "${cache_dir}"

## Seed: sudo-copy previously-cached .debs into the root-owned apt
## archive. nullglob makes the empty case (first run / cleared
## cache) a no-op array.
seed_debs=("${cache_dir}/"*.deb)
if [ "${#seed_debs[@]}" -gt 0 ]; then
   sudo cp --no-clobber -- "${seed_debs[@]}" /var/cache/apt/archives/
fi

sudo --non-interactive -- apt-get update --error-on=any
sudo --non-interactive -- apt-get install --yes --no-install-recommends -- "${@}"

## Snapshot: copy newly-downloaded .debs back into the runner-owned
## cache directory for the next run. apt's .debs are root:root mode
## 0644 (world-readable), so plain cp as runner works; resulting
## files in cache_dir are runner-owned, which is what actions/cache
## needs to tar them on the post-step.
new_debs=(/var/cache/apt/archives/*.deb)
if [ "${#new_debs[@]}" -gt 0 ]; then
   cp --no-clobber -- "${new_debs[@]}" "${cache_dir}/"
fi
