#!/bin/bash

## Copyright (C) 2026 - 2026 ENCRYPTED SUPPORT LLC <adrelanos@whonix.org>
## See the file COPYING for copying conditions.

## AI-Assisted

## Mock-API test: dm-github-org-metadata-sync --dry-run produces
## DRY-RUN lines for each (owner, repo) listed in repo-metadata.bsh
## that actually exists on the owner, and a per-owner summary count of
## present-vs-absent. Default owner set is org-ai-assisted; the
## fixture has derivative-maker and helper-scripts present (both are
## listed in repo-metadata.bsh) plus some-fork and a couple filtered-
## out repos (private / archived). some-fork is not in
## repo-metadata.bsh, so it should fall into "absent" from the tool's
## perspective.

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
out="$(dm-github-org-metadata-sync --dry-run 2>&1)" || rc=$?

fail=0

if [ "${rc}" -ne 0 ]; then
   printf '%s\n' "FAIL: --dry-run exited non-zero (rc='${rc}')" >&2
   fail=1
fi

## derivative-maker and helper-scripts both live in
## repo-metadata.bsh AND in the org-ai-assisted fixture. Expect two
## DRY-RUN lines per repo (PATCH metadata + PUT topics).
required=(
   'DRY-RUN: org-ai-assisted/derivative-maker: description + homepage -> PATCH /repos/org-ai-assisted/derivative-maker'
   'DRY-RUN: org-ai-assisted/derivative-maker: topics -> PUT /repos/org-ai-assisted/derivative-maker/topics'
   'DRY-RUN: org-ai-assisted/helper-scripts: description + homepage -> PATCH /repos/org-ai-assisted/helper-scripts'
   'DRY-RUN: org-ai-assisted/helper-scripts: topics -> PUT /repos/org-ai-assisted/helper-scripts/topics'
   ## Repo-metadata.bsh has 108 entries; 2 are present on the fixture,
   ## so the summary reports 2 present and 106 absent.
   "org-ai-assisted: '2' repos with metadata, '106' absent (skipped)"
)

## some-fork is on the org fixture but is NOT in repo-metadata.bsh -
## it must not produce any DRY-RUN lines.
forbidden=(
   'DRY-RUN: org-ai-assisted/some-fork: '
   ## Private / archived repos must not leak through the list filter.
   'DRY-RUN: org-ai-assisted/private-thing: '
   'DRY-RUN: org-ai-assisted/old-archived: '
)

for needle in "${required[@]}"; do
   ## log() runs every message through sanitize-string (helper-scripts), which
   ## maps '>' to '_', so a plan line's '->' arrow is emitted as '-_'. Sanitize
   ## each expected fragment the same way before matching -- the assertion pins
   ## the tool's intended message, not sanitize-string's glyph mapping (which
   ## helper-scripts owns and tests).
   needle="$(printf '%s' "${needle}" | sanitize-string -- nolimit)"
   if ! grep --quiet --fixed-strings -- "${needle}" <<< "${out}"; then
      printf '%s\n' "FAIL: missing expected fragment: ${needle}" >&2
      fail=1
   fi
done
for needle in "${forbidden[@]}"; do
   if grep --quiet --fixed-strings -- "${needle}" <<< "${out}"; then
      printf '%s\n' "FAIL: forbidden fragment present: ${needle}" >&2
      fail=1
   fi
done

exit "${fail}"
