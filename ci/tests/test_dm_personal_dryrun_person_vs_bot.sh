#!/bin/bash

## Copyright (C) 2026 - 2026 ENCRYPTED SUPPORT LLC <adrelanos@whonix.org>
## See the file COPYING for copying conditions.

## AI-Assisted

## Mock-API test: dm-github-personal-policy pivots its per-repo
## PATCH body on user_kind. PERSON_USERS and BOT_USERS entries
## both get the lockdown body (has_wiki/has_issues/has_projects/
## has_discussions all false; secret_scanning + push_protection
## on). The split is preserved for future divergence. Neither
## body sets
## allow_forking - GitHub's API rejects that field on user-owned
## repos with HTTP 422.
##
## Two dry-runs against fixture users in the respective arrays:
##   personal-test-user  (PERSON_USERS) -> 'PERSON: settings (...)'
##   bot-test-user       (BOT_USERS)    -> 'BOT: settings (...)'
##
## Fixtures used (under ci/fixtures/):
##   GET_users_personal-test-user, GET_users_personal-test-user_repos
##   GET_users_bot-test-user,      GET_users_bot-test-user_repos
##   plus the per-repo PATCH/PUT/DELETE/POST mocks.

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

## --- PERSON side: personal-test-user ---
rc=0
out_person="$(dm-github-personal-policy personal-test-user --dry-run 2>&1)" || rc=$?

if [ "${rc}" -ne 0 ]; then
   printf '%s\n' "FAIL: PERSON --dry-run exited rc='${rc}'" >&2
   printf '%s\n' "${out_person}" >&2
   fail=1
fi

person_required=(
   'PERSON: settings (wiki/issues/projects/discussions off, secret-scan on)'
)
person_forbidden=(
   'BOT: settings'
)
for needle in "${person_required[@]}"; do
   if ! grep --quiet --fixed-strings -- "${needle}" <<< "${out_person}"; then
      printf '%s\n' "FAIL[PERSON]: missing fragment: ${needle}" >&2
      fail=1
   fi
done
for needle in "${person_forbidden[@]}"; do
   if grep --quiet --fixed-strings -- "${needle}" <<< "${out_person}"; then
      printf '%s\n' "FAIL[PERSON]: unexpected BOT-side fragment present: ${needle}" >&2
      fail=1
   fi
done

## --- BOT side: bot-test-user ---
rc=0
out_bot="$(dm-github-personal-policy bot-test-user --dry-run 2>&1)" || rc=$?

if [ "${rc}" -ne 0 ]; then
   printf '%s\n' "FAIL: BOT --dry-run exited rc='${rc}'" >&2
   printf '%s\n' "${out_bot}" >&2
   fail=1
fi

bot_required=(
   'BOT: settings (wiki/issues/projects/discussions off, secret-scan on)'
)
bot_forbidden=(
   'PERSON: settings'
)
for needle in "${bot_required[@]}"; do
   if ! grep --quiet --fixed-strings -- "${needle}" <<< "${out_bot}"; then
      printf '%s\n' "FAIL[BOT]: missing fragment: ${needle}" >&2
      fail=1
   fi
done
for needle in "${bot_forbidden[@]}"; do
   if grep --quiet --fixed-strings -- "${needle}" <<< "${out_bot}"; then
      printf '%s\n' "FAIL[BOT]: unexpected PERSON-side fragment present: ${needle}" >&2
      fail=1
   fi
done

exit "${fail}"
