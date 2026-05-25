#!/bin/bash

## Copyright (C) 2026 - 2026 ENCRYPTED SUPPORT LLC <adrelanos@whonix.org>
## See the file COPYING for copying conditions.

## AI-Assisted

## Mock-API test: github-org-clone --dry-run lists every non-archived
## non-private repo from the source org. Forks are included by
## default (some upstream repos are themselves forks); --exclude-forks
## flips that.

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

## Capture stderr too: github-org-clone routes user-facing output
## through log notice / log warn now, all of which go to stderr.
out="$(github-org-clone --dry-run org-ai-assisted /tmp/clone-dryrun-out 2>&1)"

## Expected: three repos selected (derivative-maker, helper-scripts,
## some-fork). The other two (archived/private) are still filtered
## out by the default flags.
expected_repos=( derivative-maker helper-scripts some-fork )
unexpected=( old-archived private-thing )

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

if ! grep --quiet --fixed-strings -- '3 repos to process under' <<< "${out}"; then
  printf '%s\n' 'FAIL: expected "3 repos to process" header' >&2
  fail=1
fi

## --exclude-forks should drop some-fork from the list.
out_no_forks="$(github-org-clone --dry-run --exclude-forks \
  org-ai-assisted /tmp/clone-dryrun-out 2>&1)"
if grep --quiet -- 'DRY-RUN: clone .*some-fork\.git' <<< "${out_no_forks}"; then
  printf '%s\n' 'FAIL: --exclude-forks did not drop some-fork' >&2
  fail=1
fi
if ! grep --quiet --fixed-strings -- '2 repos to process under' <<< "${out_no_forks}"; then
  printf '%s\n' 'FAIL: --exclude-forks: expected "2 repos to process" header' >&2
  fail=1
fi

exit "${fail}"
