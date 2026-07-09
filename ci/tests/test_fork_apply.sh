#!/bin/bash

## Copyright (C) 2026 - 2026 ENCRYPTED SUPPORT LLC <adrelanos@whonix.org>
## See the file COPYING for copying conditions.

## AI-Assisted

## Mock-API test for github-org-fork --apply. Companion to
## test_fork_dryrun.sh (covers --dry-run output). Walks the entire
## apply path against fixtures: source/target listing, fork creation
## for repos missing on target, collision detection (parent.full_name
## lookup), per-repo configure_one (PATCH + PUT settings), and
## sync_one (--sync-branches via merge-upstream).
##
## Fork creation, configure_one, and sync_one are otherwise only
## smoke-exercised by test_fork_dryrun.sh's dry-run short-circuits;
## here we exercise the real ghorg_api code paths so the API
## response handling (status codes, jq extraction, name-validation
## of API-derived default_branch + parent.full_name) gets pinned.

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
out="$(github-org-fork --apply \
   --include-forks --disable-issues \
   --actions enable --workflow-perms read \
   --sync-branches --verbose \
   test-source test-target 2>&1)" || rc=$?

fail=0

if [ "${rc}" -ne 0 ]; then
   printf '%s\n' "FAIL: --apply exited non-zero (rc='${rc}')" >&2
   printf '%s\n' '--- captured output ---' >&2
   printf '%s\n' "${out}" >&2
   fail=1
fi

required=(
   ## Source/target announcement.
   'source: test-source -> target: test-target'
   ## fresh-repo is in source but not target -> fork_one POSTs and
   ## logs 'forked:'. Only the 202 success path produces this line;
   ## a missing fixture or a different status would log 'fork ...
   ## HTTP error' instead.
   'forked: test-source/fresh-repo -> test-target/fresh-repo'
   ## existing-repo is in source AND target -> configure_one runs
   ## the optional --disable-issues PATCH path, --actions enable PUT,
   ## and --workflow-perms read PUT. With --verbose all three log
   ## ok lines.
   'configured: test-target/existing-repo'
   'actions=enable on test-target/existing-repo'
   'workflow-perms=read on test-target/existing-repo'
   ## --sync-branches: sync_one looks up default_branch ('master' in
   ## the fixture) and POSTs merge-upstream. merge_type comes from
   ## the fixture body; its presence proves the success-path jq
   ## extraction works.
   "synced: test-target/existing-repo/master merge_type='fast-forward'"
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

## Filter check: existing-repo should NOT show up under "forked:"
## (it's already on target). fresh-repo should NOT show up under
## "configured:" (it's missing on target, not in to_configure).
if grep --quiet --fixed-strings -- 'forked: test-source/existing-repo' <<< "${out}"; then
   printf '%s\n' 'FAIL: existing-repo went through fork_one; should be skipped' >&2
   fail=1
fi
if grep --quiet --fixed-strings -- 'configured: test-target/fresh-repo' <<< "${out}"; then
   printf '%s\n' 'FAIL: fresh-repo went through configure_one; should be in missing not to_configure' >&2
   fail=1
fi

exit "${fail}"
