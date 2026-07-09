#!/bin/bash

## Copyright (C) 2026 - 2026 ENCRYPTED SUPPORT LLC <adrelanos@whonix.org>
## See the file COPYING for copying conditions.

## AI-Assisted

## Mock-API test for dm-github-fork-sync. The wrapper sources
## github-org-lib.bsh (transitively pulling in log_run_die.sh + has.sh
## + strings.bsh AND inheriting LOG_MAX_LEN) and spawns
## github-org-fork once per source org with the project's policy
## flags. This test pins:
##
##   1. The wrapper sources cleanly (a missing helper would die at
##      startup; the lib-level LOG_MAX_LEN default sets up the cap
##      for the wrapper's own log lines).
##   2. The wrapper iterates SOURCE_ORGS and emits one '=== src ->
##      mirror ===' header per iteration.
##   3. The spawned github-org-fork inherits the mock fixtures (env
##      passthrough) and produces dry-run output for each source
##      repo.
##
## Fixtures: per-source-org Kicksecure + Whonix as Organizations
## with one repo each. Target side reuses the existing
## org-ai-assisted fixtures.

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
out="$(dm-github-fork-sync --dry-run 2>&1)" || rc=$?

fail=0

if [ "${rc}" -ne 0 ]; then
   printf '%s\n' "FAIL: dm-github-fork-sync --dry-run exited non-zero (rc='${rc}')" >&2
   printf '%s\n' '--- captured output ---' >&2
   printf '%s\n' "${out}" >&2
   fail=1
fi

required=(
   ## Wrapper iterates SOURCE_ORGS=( Kicksecure Whonix ).
   '=== Kicksecure -> org-ai-assisted ==='
   '=== Whonix -> org-ai-assisted ==='
   ## Spawned github-org-fork echoes its source/target line for each
   ## iteration; pin one fragment per iteration.
   'source: Kicksecure -> target: org-ai-assisted'
   'source: Whonix -> target: org-ai-assisted'
   ## Per-repo dry-run from the spawned tool. Repo names come from
   ## the per-source fixtures.
   'DRY-RUN: fork Kicksecure/ks-test -> org-ai-assisted/ks-test'
   'DRY-RUN: fork Whonix/whonix-test -> org-ai-assisted/whonix-test'
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

exit "${fail}"
