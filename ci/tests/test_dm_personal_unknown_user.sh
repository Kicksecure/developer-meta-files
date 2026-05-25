#!/bin/bash

## Copyright (C) 2026 - 2026 ENCRYPTED SUPPORT LLC <adrelanos@whonix.org>
## See the file COPYING for copying conditions.

## AI-Assisted

## Mock-API test: dm-github-personal-policy refuses to run against
## a User that is in neither PERSON_USERS nor BOT_USERS.
##
## The check is structurally important: it stops a typo or a
## newly-created bot account from silently inheriting PERSON-side
## defaults (issues stay on, no allow_forking lockdown). The script
## dies with exit 64 (EX_USAGE) and a message naming both arrays.

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

fail=0
rc=0
out="$(dm-github-personal-policy unknown-test-user --dry-run 2>&1)" || rc=$?

## Expect EX_USAGE = 64 from the die_64 in user_kind() failure.
if [ "${rc}" -ne 64 ]; then
   printf '%s\n' "FAIL: expected exit 64 (EX_USAGE), got '${rc}'" >&2
   printf '%s\n' "${out}" >&2
   fail=1
fi

required=(
   ## Message must name BOTH arrays so the maintainer knows where to
   ## add the user if it should be in scope.
   'PERSON_USERS'
   'BOT_USERS'
)
for needle in "${required[@]}"; do
   if ! grep --quiet --fixed-strings -- "${needle}" <<< "${out}"; then
      printf '%s\n' "FAIL: missing fragment in error message: ${needle}" >&2
      fail=1
   fi
done

exit "${fail}"
