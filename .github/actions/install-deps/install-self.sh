#!/bin/bash

## Copyright (C) 2026 - 2026 ENCRYPTED SUPPORT LLC <adrelanos@whonix.org>
## See the file COPYING for copying conditions.

## AI-Assisted

## CI helper: install the caller repo via 'genmkfile
## <INSTALL_SELF_MODE>'. Mode 'install' file-copies the in-tree
## payload (fast, no postinst). Mode 'deb-icup' builds + apt-
## installs the .deb (postinst runs, including config-package-dev
## displace / divert).

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

INSTALL_SELF_MODE="${INSTALL_SELF_MODE:-install}"
readonly INSTALL_SELF_MODE

case "${INSTALL_SELF_MODE}" in
   install|deb-icup) ;;
   *)
      printf '%s\n' "error: INSTALL_SELF_MODE must be 'install' or 'deb-icup', got '${INSTALL_SELF_MODE}'" >&2
      exit 1
      ;;
esac

## Trailing '--' in the array terminates sudo's option parsing -
## defense in depth so a future prepended argument cannot smuggle
## a sudo flag. Same pattern as install-helper-scripts.sh.
sudo_prefix=()
if [ "$(id -u)" -ne 0 ]; then
   sudo_prefix=(sudo --non-interactive --)
fi

readonly sudo_prefix

printf '%s\n' "=== Installing caller repo via 'genmkfile ${INSTALL_SELF_MODE}' ==="
"${sudo_prefix[@]}" genmkfile "${INSTALL_SELF_MODE}"
