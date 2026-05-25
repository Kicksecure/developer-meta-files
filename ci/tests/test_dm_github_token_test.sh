#!/bin/bash

## Copyright (C) 2026 - 2026 ENCRYPTED SUPPORT LLC <adrelanos@whonix.org>
## See the file COPYING for copying conditions.

## AI-Assisted

## Mock-API test for dm-github-token-test. Walks the two-step
## health-check the operator runs before invoking the apply tools:
##   1. ghorg_authenticated_user (GET /user) - proves the token is
##      valid AND extracts a validated .login string.
##   2. /rate_limit - shows how much core REST budget remains
##      against the 5000/hr cap.
##
## Fixtures:
##   GET_user        existing
##   GET_rate_limit  added by this test (year-2050 reset epoch so
##                   `date -u -d @${epoch}` cannot underflow on a
##                   workstation with a skewed clock).

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

SCRIPT_DIR="$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" && pwd )"
FIXTURES_DIR="$(cd -- "${SCRIPT_DIR}/../fixtures" && pwd)"

export GHORG_MOCK=true
export GHORG_MOCK_DIR="${FIXTURES_DIR}"

rc=0
out="$(dm-github-token-test 2>&1)" || rc=$?

fail=0

if [ "${rc}" -ne 0 ]; then
   printf '%s\n' "FAIL: dm-github-token-test exited non-zero (rc='${rc}')" >&2
   printf '%s\n' '--- captured output ---' >&2
   printf '%s\n' "${out}" >&2
   fail=1
fi

required=(
   ## .login extracted from GET /user fixture (assisted-by-ai).
   'login: assisted-by-ai'
   ## remaining/limit pulled from GET /rate_limit fixture.
   'rate-limit core: 4500/5000'
)
for needle in "${required[@]}"; do
   if ! grep --quiet --fixed-strings -- "${needle}" <<< "${out}"; then
      printf '%s\n' "FAIL: missing expected fragment: ${needle}" >&2
      fail=1
   fi
done

## remaining=4500 is well above the 100-low-watermark, so the warn
## path must NOT fire.
if grep --quiet --fixed-strings -- 'rate-limit core remaining is low' <<< "${out}"; then
   printf '%s\n' 'FAIL: low-remaining warn fired with 4500 remaining (cap is 100)' >&2
   fail=1
fi

exit "${fail}"
