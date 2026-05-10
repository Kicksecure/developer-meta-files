#!/bin/bash

## Copyright (C) 2026 - 2026 ENCRYPTED SUPPORT LLC <adrelanos@whonix.org>
## See the file COPYING for copying conditions.

## AI-Assisted

## CI helper: assert the GHORG_AUDIT_TOKEN repo secret is set
## before invoking dm-github-policy --audit / --dry-run. The
## token-presence boolean arrives via env (resolved at the
## workflow's expression-evaluation time); the secret value itself
## never reaches this script.

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

if [ "${TOKEN_PRESENT:-}" != 'true' ]; then
   printf '%s\n' \
      'error: GHORG_AUDIT_TOKEN secret is not set on this repo.' \
      '       Add it under Settings -> Secrets and variables -> Actions.' >&2
   exit 1
fi

printf '%s\n' 'GHORG_AUDIT_TOKEN secret detected.'
