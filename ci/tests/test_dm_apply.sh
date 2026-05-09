#!/bin/bash

## Copyright (C) 2026 - 2026 ENCRYPTED SUPPORT LLC <adrelanos@whonix.org>
## See the file COPYING for copying conditions.

## AI-Assisted

## Mock-API test: dm-github-org-policy --apply walks the entire
## org-level apply path (fork-PR approval, workflow GITHUB_TOKEN,
## allowed-actions, members, code-security configuration list-create-
## attach-default, branch + tag rulesets) plus the per-repo loop
## (PATCH wiki/issues), all served from local fixtures.
##
## This is the only test that exercises the body-capture machinery in
## policy_api_call end-to-end via apply_code_security_config (where
## .id from a POST response feeds the subsequent attach + defaults
## calls) and via _policy_upsert_ruleset (where the GET-list step
## now uses policy_api_call with body capture). A regression in the
## printf -v indirection or the 6th-arg signature trips a clear
## warn here ("'X': code-security config id '...' not a valid numeric
## id") and the tool exits non-zero.
##
## Companion to test_dm_dryrun.sh (covers --dry-run output) and
## test_dm_audit.sh (covers --audit GETs); together they pin the full
## three-mode surface of dm-github-org-policy against fixtures.

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

rc=0
out="$(dm-github-org-policy --apply 2>&1)" || rc=$?

fail=0

## Exit-code check (G-043): every policy_api_call success path keeps
## policy_warn_seen=0; the tool returns non-zero iff at least one
## warn fired. A warn here would mean either an unmocked endpoint
## (ghorg_mock_dispatch -> HTTP 599) or a real bug in the apply
## path (id parse failure, unexpected status, etc.).
if [ "${rc}" -ne 0 ]; then
   printf '%s\n' "FAIL: --apply exited non-zero (rc='${rc}'); a warn slipped through" >&2
   printf '%s\n' '--- captured output ---' >&2
   printf '%s\n' "${out}" >&2
   fail=1
fi

## Substring assertions on the 'ok:' lines policy_api_call emits on
## each successful step (POLICY_QUIET_OK is not set by the org tool,
## so these are visible).
required=(
   ## Org-level apply steps:
   'ok: org-ai-assisted: fork-PR approval=all_external_contributors'
   'ok: org-ai-assisted: workflow GITHUB_TOKEN read-only, no PR approval'
   'ok: org-ai-assisted: actions enabled=all, allowed=selected'
   'ok: org-ai-assisted: selected-actions = github-owned + verified-creators'
   'ok: org-ai-assisted: members policy (default-perm=read, no member create)'

   ## apply_code_security_config: list -> create (body-capture reads
   ## .id) -> attach -> default. The 'created code-security
   ## configuration id=' line is the one that proves the captured
   ## body parsed correctly; without it the attach + default calls
   ## would target an empty id and warn.
   'ok: org-ai-assisted: created code-security configuration id='
   'ok: org-ai-assisted: attach code-security config to all repos'
   'ok: org-ai-assisted: set code-security config as default for new repos'

   ## _policy_upsert_ruleset list-then-create path. The 'list
   ## rulesets' ok line is what proves policy_api_call's body-
   ## capture works on the GET path (it feeds existing_id detection).
   'ok: org-ai-assisted: list rulesets'
   "create ruleset 'dm-github-org-policy default-branch protection'"
   "create ruleset 'dm-github-org-policy tag protection'"

   ## Per-repo apply path. Three in-scope repos in the fixture
   ## (forks now included since dm-github-org-policy switched
   ## inc_forks=1). org-ai-assisted is a MIRROR_ORGS entry, so the
   ## body+label come from POLICY_REPO_MIRROR.
   'ok: org-ai-assisted/derivative-maker: MIRROR: wiki=off, issues=off, projects=off, discussions=off, allow_forking=off'
   'ok: org-ai-assisted/helper-scripts: MIRROR: wiki=off, issues=off, projects=off, discussions=off, allow_forking=off'
   'ok: org-ai-assisted/some-fork: MIRROR: wiki=off, issues=off, projects=off, discussions=off, allow_forking=off'
)
for needle in "${required[@]}"; do
   if ! grep --quiet --fixed-strings -- "${needle}" <<< "${out}"; then
      printf '%s\n' "FAIL: missing expected fragment: ${needle}" >&2
      fail=1
   fi
done

## Filter check: archived / fork / private repos must be skipped
## (ghorg_list_repos jq filter), so no PATCH for them.
forbidden=(
   'old-archived: wiki=off'
   'some-fork: wiki=off'
   'private-thing: wiki=off'
)
for needle in "${forbidden[@]}"; do
   if grep --quiet --fixed-strings -- "${needle}" <<< "${out}"; then
      printf '%s\n' "FAIL: filtered-out repo reached the apply loop: ${needle}" >&2
      fail=1
   fi
done

exit "${fail}"
