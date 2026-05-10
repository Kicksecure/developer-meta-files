#!/bin/bash

## Copyright (C) 2026 - 2026 ENCRYPTED SUPPORT LLC <adrelanos@whonix.org>
## See the file COPYING for copying conditions.

## AI-Assisted

## CI helper: install helper-scripts from its upstream git
## repository using the genmkfile install flow. helper-scripts
## provides sanitize-string and supporting Python packages used by
## safe-print paths in the org's bash libraries.
##
## Depends on genmkfile already being installed on PATH (see
## install-genmkfile.sh).
##
## Context-aware sudo: works both in a root container and on a
## non-root host runner.
##
## Org resolution: defaults to Kicksecure (the canonical upstream).
## Override with HELPER_SCRIPTS_OWNER env var when running from a
## mirror org. The composite-action wrapper sets
## HELPER_SCRIPTS_OWNER to the caller input or, by default,
## github.repository_owner.

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

if ! command -v genmkfile >/dev/null 2>&1; then
   printf '%s\n' \
      'error: genmkfile not on PATH; run install-genmkfile.sh first.' >&2
   exit 1
fi

sudo_prefix=()
if [ "$(id -u)" -ne 0 ]; then
   sudo_prefix=(sudo --non-interactive)
fi

readonly sudo_prefix
readonly clone_dir='/tmp/helper-scripts-install'
readonly upstream_owner="${HELPER_SCRIPTS_OWNER:-Kicksecure}"
readonly upstream_url="https://github.com/${upstream_owner}/helper-scripts.git"

git clone --depth=1 --no-tags --branch=master -- "${upstream_url}" "${clone_dir}"
cd -- "${clone_dir}"
GENMKFILE_DEBUG=1 "${sudo_prefix[@]}" genmkfile install
