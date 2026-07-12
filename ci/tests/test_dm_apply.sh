#!/bin/bash

## Copyright (C) 2026 - 2026 ENCRYPTED SUPPORT LLC <adrelanos@whonix.org>
## See the file COPYING for copying conditions.

## AI-Assisted

## Mock-API test: dm-github-org-policy --apply walks the
## Free-plan-compatible org-level apply path (fork-PR approval,
## workflow GITHUB_TOKEN, allowed-actions, members) plus the per-
## repo loop (PATCH wiki/issues), all served from local fixtures.
##
## The code-security configuration list-create-attach-default flow
## and the org-level branch + tag ruleset upserts are PAID PLAN
## ONLY (GHAS / GitHub Team+) and are commented out in
## dm-github-org-policy + github-policy-data.bsh; this test reflects
## that elision and instead asserts the corresponding 'skip:' lines
## are emitted so an operator sees what was bypassed.
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
FIXTURES_DIR="$(cd -- "${SCRIPT_DIR}/../fixtures" && pwd)"

export GHORG_MOCK=true
export GHORG_MOCK_DIR="${FIXTURES_DIR}"

rc=0
out="$(ORGS_OVERRIDE='org-ai-assisted' dm-github-org-policy --apply 2>&1)" || rc=$?

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
   'ok: org-ai-assisted: members policy (default-perm=read, no member create, no deploy keys)'

   ## PAID PLAN ONLY: code-security configuration + org rulesets
   ## are commented out in dm-github-org-policy. The two skip lines
   ## are the contract that operator-facing log shows what was
   ## elided.
   'skip: org-ai-assisted: code-security configuration - PAID PLAN ONLY'
   'skip: org-ai-assisted: org-level branch + tag rulesets - PAID PLAN ONLY'

   ## Per-repo apply path. Three in-scope repos in the fixture
   ## (forks now included since dm-github-org-policy switched
   ## inc_forks=1). org-ai-assisted is a MIRROR_ORGS entry, so the
   ## body+label come from POLICY_REPO_MIRROR.
   'ok: org-ai-assisted/derivative-maker: MIRROR: wiki/issues/projects/discussions off, secret-scan on'
   'ok: org-ai-assisted/helper-scripts: MIRROR: wiki/issues/projects/discussions off, secret-scan on'
   'ok: org-ai-assisted/some-fork: MIRROR: wiki/issues/projects/discussions off, secret-scan on'

   ## Dependabot/PVR are actively disabled on MIRROR (org-ai-
   ## assisted) so every --apply reconciles state. Order:
   ## security-fixes BEFORE alerts. The fixture returns 422 on
   ## DELETE /automated-security-fixes to exercise the
   ## EXTRA_OK_STATUS=422 path; the policy treats 422 as success
   ## (idempotent steady state) so the line still emits 'ok:'.
   ## Asserted on one repo (the disable trio is symmetric across
   ## all three).
   'ok: org-ai-assisted/derivative-maker: disable Dependabot security updates (mirror)'
   'ok: org-ai-assisted/derivative-maker: disable Dependabot alerts (mirror)'
   'ok: org-ai-assisted/derivative-maker: disable private vulnerability reporting'

   ## Free-plan-compatible per-repo branch + tag rulesets. Applied
   ## on both SOURCE and MIRROR (only the bypass actor list
   ## differs). The fixture's GET /rulesets returns [] so the
   ## upsert path falls through to a POST 'create ruleset' for each.
   "org-ai-assisted/derivative-maker: create ruleset 'dm-github-org-policy default-branch protection'"
   "org-ai-assisted/derivative-maker: create ruleset 'dm-github-org-policy tag protection'"
)

## MIRROR must NOT see SOURCE-only enable ok lines (those would
## indicate apply_repo_policy fell through the kind=='source'
## branch incorrectly). PVR enable also must never appear; see
## agents/github-policy-canonical-vs-mirror.md for the policy.
mirror_dep_pvr_forbidden=(
   'ok: org-ai-assisted/derivative-maker: enable Dependabot alerts'
   'ok: org-ai-assisted/derivative-maker: enable Dependabot security updates'
   'ok: org-ai-assisted/derivative-maker: enable private vulnerability reporting'
)
for needle in "${mirror_dep_pvr_forbidden[@]}"; do
   if grep --quiet --fixed-strings -- "${needle}" <<< "${out}"; then
      printf '%s\n' "FAIL: SOURCE-only line leaked to MIRROR: ${needle}" >&2
      fail=1
   fi
done
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
