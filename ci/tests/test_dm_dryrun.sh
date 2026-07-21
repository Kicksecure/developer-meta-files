#!/bin/bash

## Copyright (C) 2026 - 2026 ENCRYPTED SUPPORT LLC <adrelanos@whonix.org>
## See the file COPYING for copying conditions.

## AI-Assisted

## Mock-API test: dm-github-org-policy --dry-run produces DRY-RUN: prefixed
## lines for each planned API call without making any writes. Covers
## the org-level apply path; the per-repo loop uses ghorg_list_repos
## (read GET) and per-repo PATCHes also flagged DRY-RUN:.

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

## Capture combined stdout+stderr; the lib routes everything through
## log_run_die.sh's stecho >&2.
rc=0
out="$(ORGS_OVERRIDE='org-ai-assisted' dm-github-org-policy --dry-run 2>&1)" || rc=$?

fail=0

## Dry-run does no real API calls (policy_api_call short-circuits
## before ghorg_api), so no warn path can fire and exit must be 0.
## A non-zero exit here means dm-github-org-policy's POLICY_WARN_FILE
## flag ended up non-empty, i.e. a warn slipped through somewhere
## the lib structurally said it could not - investigate before
## papering over. Exit-code check replaces the prior brittle
## "no [WARN]: in output" regex.
if [ "${rc}" -ne 0 ]; then
   printf '%s\n' "FAIL: --dry-run exited non-zero (rc='${rc}'); a warn slipped through" >&2
   fail=1
fi

required=(
   'DRY-RUN: org-ai-assisted: fork-PR approval=all_external_contributors'
   'DRY-RUN: org-ai-assisted: workflow GITHUB_TOKEN read-only, no PR approval'
   'DRY-RUN: org-ai-assisted: actions enabled=all, allowed=selected'
   'DRY-RUN: org-ai-assisted: selected-actions = github-owned + verified-creators'
   'DRY-RUN: org-ai-assisted: members policy (default-perm=read, no member create, no deploy keys)'
   'skip: org-ai-assisted: 2FA enforcement must be set via UI'
   ## PAID PLAN ONLY (commented out in dm-github-org-policy):
   ## code-security configuration upsert/attach/default and the
   ## org-level branch + tag ruleset upserts. The skip lines below
   ## stand in for those.
   'skip: org-ai-assisted: code-security configuration - PAID PLAN ONLY'
   'skip: org-ai-assisted: org-level branch + tag rulesets - PAID PLAN ONLY'
   'skip: org-ai-assisted: PAT policy toggles must be set via UI'
   'skip: org-ai-assisted: GitHub App / OAuth App policies must be set via UI'

   ## MIRROR (org-ai-assisted) actively disables Dependabot/PVR
   ## via DELETE on the same three endpoints. Per-repo branch +
   ## tag rulesets apply on both SOURCE and MIRROR.
   'DRY-RUN: org-ai-assisted/derivative-maker: disable Dependabot security updates (mirror)'
   'DRY-RUN: org-ai-assisted/derivative-maker: disable Dependabot alerts (mirror)'
   'DRY-RUN: org-ai-assisted/derivative-maker: disable private vulnerability reporting'
   'DRY-RUN: org-ai-assisted/derivative-maker: upsert ruleset dm-github-org-policy default-branch protection'
   'DRY-RUN: org-ai-assisted/derivative-maker: upsert ruleset dm-github-org-policy tag protection'
)

## MIRROR must NOT see SOURCE-only enable DRY-RUN lines. PVR enable
## also must never appear; see agents/github-policy-canonical-vs-
## mirror.md for the policy.
mirror_dep_pvr_forbidden=(
   'DRY-RUN: org-ai-assisted/derivative-maker: enable Dependabot alerts'
   'DRY-RUN: org-ai-assisted/derivative-maker: enable Dependabot security updates'
   'DRY-RUN: org-ai-assisted/derivative-maker: enable private vulnerability reporting'
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

exit "${fail}"
