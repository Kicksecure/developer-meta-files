#!/bin/bash

## Copyright (C) 2026 - 2026 ENCRYPTED SUPPORT LLC <adrelanos@whonix.org>
## See the file COPYING for copying conditions.

## AI-Assisted

## Mock-API test: dm-github-org-policy pivots its per-repo PATCH
## body on org_kind. SOURCE_ORGS entries (Kicksecure, Whonix) get
## the SOURCE body (has_issues: true, no allow_forking field).
## MIRROR_ORGS entries (org-ai-assisted) get the MIRROR body
## (has_issues: false, allow_forking: false).
##
## Two separate dry-runs:
##   ORGS=( 'Whonix' )           -> expect 'SOURCE: wiki=off, issues=on'
##   ORGS=( 'org-ai-assisted' )  -> expect 'MIRROR: ...' (no allow_forking - org level only)
##
## The SOURCE/MIRROR split for the org-level branch-ruleset bypass
## actor list (POLICY_RULESET_BYPASS_SOURCE/MIRROR) is currently
## inert because the org-level ruleset upsert is PAID PLAN ONLY
## (commented out in dm-github-org-policy on Free); the bypass-list
## pivot is exercised again once the org upgrades to GitHub Team+.

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

fail=0

## --- SOURCE side: Whonix ---
rc=0
out_source="$(ORGS_OVERRIDE='Whonix' dm-github-org-policy --dry-run 2>&1)" || rc=$?

if [ "${rc}" -ne 0 ]; then
   printf '%s\n' "FAIL: --dry-run on SOURCE org Whonix exited rc='${rc}'" >&2
   printf '%s\n' "${out_source}" >&2
   fail=1
fi

source_required=(
   ## SOURCE per-repo body: has_issues stays on, no allow_forking
   ## field at all (the body simply omits it).
   'SOURCE: wiki=off, issues=on'
)
source_forbidden=(
   ## MIRROR-specific tokens MUST NOT appear when running against a
   ## SOURCE org.
   'MIRROR:'
)
for needle in "${source_required[@]}"; do
   if ! grep --quiet --fixed-strings -- "${needle}" <<< "${out_source}"; then
      printf '%s\n' "FAIL[SOURCE]: missing expected fragment: ${needle}" >&2
      fail=1
   fi
done
for needle in "${source_forbidden[@]}"; do
   if grep --quiet --fixed-strings -- "${needle}" <<< "${out_source}"; then
      printf '%s\n' "FAIL[SOURCE]: unexpected MIRROR-side fragment present: ${needle}" >&2
      fail=1
   fi
done

## --- MIRROR side: org-ai-assisted ---
rc=0
out_mirror="$(ORGS_OVERRIDE='org-ai-assisted' dm-github-org-policy --dry-run 2>&1)" || rc=$?

if [ "${rc}" -ne 0 ]; then
   printf '%s\n' "FAIL: --dry-run on MIRROR org org-ai-assisted exited rc='${rc}'" >&2
   printf '%s\n' "${out_mirror}" >&2
   fail=1
fi

mirror_required=(
   'MIRROR: wiki=off, issues=off, projects=off, discussions=off'
)
mirror_forbidden=(
   'SOURCE:'
)
for needle in "${mirror_required[@]}"; do
   if ! grep --quiet --fixed-strings -- "${needle}" <<< "${out_mirror}"; then
      printf '%s\n' "FAIL[MIRROR]: missing expected fragment: ${needle}" >&2
      fail=1
   fi
done
for needle in "${mirror_forbidden[@]}"; do
   if grep --quiet --fixed-strings -- "${needle}" <<< "${out_mirror}"; then
      printf '%s\n' "FAIL[MIRROR]: unexpected SOURCE-side fragment present: ${needle}" >&2
      fail=1
   fi
done

exit "${fail}"
