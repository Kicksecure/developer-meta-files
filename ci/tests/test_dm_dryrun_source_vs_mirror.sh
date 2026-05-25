#!/bin/bash

## Copyright (C) 2026 - 2026 ENCRYPTED SUPPORT LLC <adrelanos@whonix.org>
## See the file COPYING for copying conditions.

## AI-Assisted

## agents/github-policy-canonical-vs-mirror.md
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
FIXTURES_DIR="$(cd -- "${SCRIPT_DIR}/../fixtures" && pwd)"

export GHORG_MOCK=true
export GHORG_MOCK_DIR="${FIXTURES_DIR}"

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
   ## SOURCE-only UI-flip skip lines (no REST setter as of 2026-05);
   ## see agents/github-policy-canonical-vs-mirror.md "SOURCE-side
   ## UI-only operator flips".
   'Dependabot grouped security updates: enable in UI'
   'Code scanning: recommend security-extended query suite'
   'Auto-triage rule "Dismiss low-impact dev-scoped" must be OFF'
   'Auto-triage rule "Dismiss package malware alerts" must be OFF'
   'Prevent direct Dependabot alert dismissals (delegated dismissal): enable in UI'
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
      printf '%s\n' "FAIL[SOURCE]: forbidden fragment present: ${needle}" >&2
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
   ## SOURCE-only UI-flip skip lines MUST NOT appear on MIRROR.
   'Dependabot grouped security updates: enable in UI'
   'Code scanning: recommend security-extended query suite'
   'Auto-triage rule "Dismiss low-impact dev-scoped"'
   'Auto-triage rule "Dismiss package malware alerts"'
   'Prevent direct Dependabot alert dismissals'
)
for needle in "${mirror_required[@]}"; do
   if ! grep --quiet --fixed-strings -- "${needle}" <<< "${out_mirror}"; then
      printf '%s\n' "FAIL[MIRROR]: missing expected fragment: ${needle}" >&2
      fail=1
   fi
done
for needle in "${mirror_forbidden[@]}"; do
   if grep --quiet --fixed-strings -- "${needle}" <<< "${out_mirror}"; then
      printf '%s\n' "FAIL[MIRROR]: forbidden fragment present: ${needle}" >&2
      fail=1
   fi
done

exit "${fail}"
