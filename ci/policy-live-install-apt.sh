#!/bin/bash

## Copyright (C) 2026 - 2026 ENCRYPTED SUPPORT LLC <adrelanos@whonix.org>
## See the file COPYING for copying conditions.

## AI-Assisted

## CI helper: install the apt pre-reqs the live-policy workflow
## needs before genmkfile and helper-scripts can be installed.
## Runs inside the workflow's debian:trixie container.

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

export DEBIAN_FRONTEND=noninteractive

apt-get update
apt-get install --yes --no-install-recommends -- \
   ca-certificates \
   curl \
   jq \
   git \
   sudo \
   build-essential \
   dctrl-tools \
   python3 \
   safe-rm
