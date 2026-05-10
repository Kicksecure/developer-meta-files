#!/bin/bash

## Copyright (C) 2026 - 2026 ENCRYPTED SUPPORT LLC <adrelanos@whonix.org>
## See the file COPYING for copying conditions.

## AI-Assisted

## Mock-API test: dm-github-org-policy pivots three things on
## org_kind. SOURCE_ORGS entries (Kicksecure, Whonix) and
## MIRROR_ORGS entries (org-ai-assisted) diverge as follows:
##
##   per-repo PATCH body:
##     SOURCE: 'wiki=off, issues=on, secret-scan on' (issues stay on)
##     MIRROR: 'wiki/issues/projects/discussions off, secret-scan on'
##
##   Dependabot alerts + Dependabot security updates:
##     SOURCE: enabled per repo (2 PUTs each)
##     MIRROR: actively disabled per repo (2 DELETEs each, with
##             security-fixes BEFORE alerts to avoid 422). Every
##             --apply reconciles - mirror would duplicate every
##             alert the canonical SOURCE repo already raises.
##
##   PVR (Private Vulnerability Reporting):
##     OFF EVERYWHERE. DELETE /private-vulnerability-reporting
##     runs on both SOURCE and MIRROR; canonical disclosure is
##     the wiki per .github/SECURITY.md. PUT enable-side has no
##     constant in github-policy-data.bsh.
##
##   per-repo branch + tag rulesets: applied on both; bypass actor
##     list pivots on POLICY_RULESET_BYPASS_SOURCE/MIRROR (the
##     repo-level ruleset upserts work on Free for public repos).
##
## The org-level ruleset upsert in apply_org_policy is PAID PLAN
## ONLY (commented out); not exercised here.

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
   'SOURCE: wiki=off, issues=on, secret-scan on'
   ## SOURCE gets the Dependabot enable fan-out.
   'enable Dependabot alerts'
   'enable Dependabot security updates'
   ## PVR is disabled on SOURCE too (wiki is canonical disclosure
   ## channel per .github/SECURITY.md).
   'disable private vulnerability reporting'
)
source_forbidden=(
   ## MIRROR-specific tokens MUST NOT appear when running against a
   ## SOURCE org.
   'MIRROR:'
   ## MIRROR-only Dependabot disable lines MUST NOT appear on
   ## SOURCE. PVR disable IS expected on both (see source_required).
   'disable Dependabot alerts'
   'disable Dependabot security updates'
   ## PVR enable line MUST NOT appear anywhere (the PUT-style
   ## constant was removed - github-policy-data.bsh has only the
   ## DELETE variant).
   'enable private vulnerability reporting'
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
   'MIRROR: wiki/issues/projects/discussions off, secret-scan on'
   ## MIRROR actively disables Dependabot via DELETE; PVR-OFF is
   ## the same call run on both sides.
   'disable Dependabot alerts'
   'disable Dependabot security updates'
   'disable private vulnerability reporting'
)
mirror_forbidden=(
   'SOURCE:'
   ## SOURCE-only Dependabot enable lines MUST NOT appear on
   ## MIRROR.
   'enable Dependabot alerts'
   'enable Dependabot security updates'
   ## PVR enable MUST NOT appear anywhere; only the DELETE
   ## (disable) form exists.
   'enable private vulnerability reporting'
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
