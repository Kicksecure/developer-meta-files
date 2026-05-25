#!/bin/bash

## Copyright (C) 2026 - 2026 ENCRYPTED SUPPORT LLC <adrelanos@whonix.org>
## See the file COPYING for copying conditions.

## AI-Assisted

## Mock-API test: dm-github-personal-policy refuses to run against
## an Organization account. ghorg_validate_name only checks the
## string format, so 'org-ai-assisted' would pass that step; the
## explicit ghorg_account_type check downstream is what protects
## the operator from accidentally applying the personal-mirror
## lockdown (Actions disabled, default-branch ruleset, etc.) across
## an entire org's public repos.
##
## Fixture used:
##   GET_users_org-ai-assisted  ('type':'Organization')

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
out="$(dm-github-personal-policy org-ai-assisted --dry-run 2>&1)" || rc=$?

fail=0
if [ "${rc}" -eq 0 ]; then
   printf '%s\n' "FAIL: expected non-zero exit on Organization input, got '${rc}'" >&2
   fail=1
fi

## The failure message must name the offending account type so the
## operator can tell what went wrong without rerunning under -x.
if ! grep --quiet --fixed-strings -- "account type 'Organization'" <<< "${out}"; then
   printf '%s\n' \
      "FAIL: refusal message did not name the offending account type:" \
      "${out}" >&2
   fail=1
fi

## Refusal must happen BEFORE any apply-side line ran. Specifically
## no DRY-RUN: line should appear - reaching that point means the
## per-repo loop started, which means the guard didn't fire.
if grep --quiet -- 'DRY-RUN:' <<< "${out}"; then
   printf '%s\n' \
      'FAIL: refusal happened too late - DRY-RUN: line slipped through' >&2
   fail=1
fi

exit "${fail}"
