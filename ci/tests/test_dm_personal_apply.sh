#!/bin/bash

## Copyright (C) 2026 - 2026 ENCRYPTED SUPPORT LLC <adrelanos@whonix.org>
## See the file COPYING for copying conditions.

## AI-Assisted

## Mock-API test: dm-github-personal-policy --apply walks the per-
## repo lockdown path against fixtures. Companion to
## test_dm_personal_dryrun.sh (covers --dry-run output). This is the
## only test that exercises:
##
##   - _policy_upsert_ruleset with scope=repo (the repo-level variant
##     of the ruleset upsert logic that test_dm_apply.sh covers only
##     in the org-level form)
##   - the 5th-arg "extra_ok" parameter of policy_api_call (used for
##     the DELETE /repos/X/Y/pages endpoint, where 404 = "no Pages
##     site" is a documented success-equivalent and must NOT trip
##     the warn flag)
##
## Two fixture repos in scope: backup-mirror (DELETE pages -> 204)
## and upstream-fork (DELETE pages -> 404, exercising the extra_ok
## path). Both must run through all 7 apply steps cleanly.

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

## --verbose forces the lib's POLICY_QUIET_OK=0 path so the per-
## step 'ok:' lines this test asserts on are emitted. Without
## --verbose, dm-github-personal-policy sets POLICY_QUIET_OK=1 by
## default and only the warns (and DRY-RUN: lines, n/a here) reach
## stdout/stderr.
rc=0
out="$(dm-github-personal-policy personal-test-user --apply --verbose 2>&1)" || rc=$?

fail=0

if [ "${rc}" -ne 0 ]; then
   printf '%s\n' "FAIL: --apply exited non-zero (rc='${rc}'); a warn slipped through" >&2
   printf '%s\n' '--- captured output ---' >&2
   printf '%s\n' "${out}" >&2
   fail=1
fi

required=(
   ## Account-wide email-visibility step. The GET_user fixture
   ## returns login=assisted-by-ai while the target here is
   ## personal-test-user; the script must SKIP the
   ## /user/email/visibility PATCH because /user/* endpoints
   ## act on the token-authed user, not the path-specified one.
   ## The skip line carries the diagnostic operators need to
   ## understand what to do (run with target's own token).
   "skip: personal-test-user: hide primary email from public profile - token belongs to 'assisted-by-ai', not 'personal-test-user'"

   ## Per-repo apply steps for backup-mirror (Pages DELETE -> 204):
   'ok: personal-test-user/backup-mirror: fork-PR approval=all_external_contributors'
   'ok: personal-test-user/backup-mirror: workflow GITHUB_TOKEN read-only'
   'ok: personal-test-user/backup-mirror: actions enabled=false (CI runs disabled)'
   'ok: personal-test-user/backup-mirror: PERSON: settings (wiki/issues/projects/discussions off, secret-scan on)'
   'ok: personal-test-user/backup-mirror: delete Pages site (if any)'
   ## Repo-level _policy_upsert_ruleset hits BOTH list (GET) AND
   ## create (POST) - the GET step uses policy_api_call with body-
   ## capture so a regression in body-capture would empty existing_id
   ## and short-circuit BEFORE the POST. Both ok lines below
   ## therefore depend on body-capture working correctly.
   'ok: personal-test-user/backup-mirror: list rulesets'
   "create ruleset 'dm-github-personal-policy default-branch protection'"
   "create ruleset 'dm-github-personal-policy tag protection'"

   ## Per-repo apply steps for upstream-fork (Pages DELETE -> 404,
   ## extra_ok argument absorbs it):
   'ok: personal-test-user/upstream-fork: fork-PR approval=all_external_contributors'
   'ok: personal-test-user/upstream-fork: actions enabled=false (CI runs disabled)'
   ## The 5th-arg extra_ok=404 path: a 404 here MUST be treated as
   ## success, not a warn. policy_api_call's case statement
   ## interpolates ${extra_ok} as a literal alternative; if the
   ## dispatch were broken the 404 would fall through to warn and rc
   ## would be 1 (already checked above). Belt-and-suspenders: also
   ## assert the ok line.
   'ok: personal-test-user/upstream-fork: delete Pages site (if any) [404]'
   'ok: personal-test-user/upstream-fork: list rulesets'
)
for needle in "${required[@]}"; do
   if ! grep --quiet --fixed-strings -- "${needle}" <<< "${out}"; then
      printf '%s\n' "FAIL: missing expected fragment: ${needle}" >&2
      fail=1
   fi
done

## Filter check: archived repos must be skipped (ghorg_list_repos
## with inc_archived=0). old-archived in the fixture must NOT reach
## the apply path.
if grep --quiet --fixed-strings -- 'old-archived' <<< "${out}"; then
   printf '%s\n' 'FAIL: archived repo reached apply loop; should be filtered' >&2
   fail=1
fi

exit "${fail}"
