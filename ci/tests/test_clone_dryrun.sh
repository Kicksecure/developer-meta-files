#!/bin/bash

## Copyright (C) 2026 - 2026 ENCRYPTED SUPPORT LLC <adrelanos@whonix.org>
## See the file COPYING for copying conditions.

## AI-Assisted

## Mock-API test: github-org-clone --dry-run lists exactly the
## non-archived non-fork non-private repos from the source org.

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
FIXTURE_DIR="$(cd -- "${SCRIPT_DIR}/../fixtures" && pwd)"

export GHORG_MOCK=1
export GHORG_MOCK_DIR="${FIXTURE_DIR}"

## Capture stderr too: github-org-clone routes user-facing output
## through log notice / log warn now, all of which go to stderr.
out="$(github-org-clone --dry-run org-ai-assisted /tmp/clone-dryrun-out 2>&1)"

## Expected: exactly two repos selected (derivative-maker,
## helper-scripts). The other three (archived/fork/private) must be
## filtered out by the default flags.
expected_repos=( derivative-maker helper-scripts )
unexpected=( old-archived some-fork private-thing )

fail=0
for repo in "${expected_repos[@]}"; do
  if ! grep --quiet -- "DRY-RUN: clone .*${repo}\.git" <<< "${out}"; then
    printf '%s\n' "FAIL: expected ${repo} in dry-run output" >&2
    fail=1
  fi
done
for repo in "${unexpected[@]}"; do
  if grep --quiet -- "DRY-RUN: clone .*${repo}\.git" <<< "${out}"; then
    printf '%s\n' "FAIL: ${repo} should be filtered out" >&2
    fail=1
  fi
done

if ! grep --quiet --fixed-strings -- '2 repos to process under' <<< "${out}"; then
  printf '%s\n' 'FAIL: expected "2 repos to process" header' >&2
  fail=1
fi

exit "${fail}"
