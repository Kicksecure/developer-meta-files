#!/bin/bash

## Copyright (C) 2026 - 2026 ENCRYPTED SUPPORT LLC <adrelanos@whonix.org>
## See the file COPYING for copying conditions.

## AI-Assisted

## Mock-API test: github-org-fork --dry-run plans forks for the
## missing repos when target is a User account that matches the
## auth user.

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

## GET_user fixture returns login=assisted-by-ai, matching target.
## Source org-ai-assisted has 2 selected repos (derivative-maker,
## helper-scripts after default filters). Target user already has
## derivative-maker. Expected: dry-run plans 1 new fork (helper-scripts).
out="$(github-org-fork --dry-run org-ai-assisted assisted-by-ai 2>&1)"

## log() sanitizes every message via sanitize-string (helper-scripts), which maps
## '>' to '_'; sanitize the expected fork line the same way before matching.
fork_line="$(printf '%s' 'DRY-RUN: fork org-ai-assisted/helper-scripts -> assisted-by-ai/helper-scripts' | sanitize-string -- nolimit)"
if ! grep --quiet -- "${fork_line}" <<< "${out}"; then
  printf '%s\n' 'FAIL: expected fork plan for helper-scripts' "${out}" >&2
  exit 1
fi
if grep --quiet -- 'DRY-RUN: fork org-ai-assisted/derivative-maker' <<< "${out}"; then
  printf '%s\n' \
    'FAIL: derivative-maker already exists, should not be re-forked' "${out}" >&2
  exit 1
fi
if grep --quiet -- 'fork org-ai-assisted/old-archived\|fork org-ai-assisted/some-fork\|fork org-ai-assisted/private-thing' <<< "${out}"; then
  printf '%s\n' 'FAIL: filtered repos appeared in fork plan' "${out}" >&2
  exit 1
fi

exit 0
