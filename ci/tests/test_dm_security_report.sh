#!/bin/bash

## Copyright (C) 2026 - 2026 ENCRYPTED SUPPORT LLC <adrelanos@whonix.org>
## See the file COPYING for copying conditions.

## AI-Assisted

## Mock-API test: dm-github-org-security-report against the
## GET_orgs_org-ai-assisted_code-scanning_alerts fixture (1
## CodeQL + 2 Scorecard alerts). Verifies:
##
##   --report  -> only the CodeQL line appears (Scorecard tools
##                filtered out by CODE_TOOLS_RE)
##   --all     -> all 3 lines appear
##
## Both modes must emit the markdown header rows (table title +
## divider).

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

## --- --report mode: code-fixable tools only ---
rc=0
out_report="$(ORGS_OVERRIDE='org-ai-assisted' dm-github-org-security-report --report 2>/dev/null)" || rc=$?

if [ "${rc}" -ne 0 ]; then
   printf '%s\n' "FAIL: --report exited rc='${rc}'" >&2
   printf '%s\n' "${out_report}" >&2
   fail=1
fi

report_required=(
   '| repo | tool | severity | rule | path | line | message |'
   '| org-ai-assisted/msgcollector | CodeQL | warning | py/file-not-closed |'
)
report_forbidden=(
   ## Scorecard alerts MUST be filtered out in --report mode.
   'MaintainedID'
   'PinnedDependenciesID'
)
for needle in "${report_required[@]}"; do
   if ! grep --quiet --fixed-strings -- "${needle}" <<< "${out_report}"; then
      printf '%s\n' "FAIL[--report]: missing fragment: ${needle}" >&2
      fail=1
   fi
done
for needle in "${report_forbidden[@]}"; do
   if grep --quiet --fixed-strings -- "${needle}" <<< "${out_report}"; then
      printf '%s\n' "FAIL[--report]: Scorecard rule leaked through filter: ${needle}" >&2
      fail=1
   fi
done

## --- --all mode: every alert ---
rc=0
out_all="$(ORGS_OVERRIDE='org-ai-assisted' dm-github-org-security-report --all 2>/dev/null)" || rc=$?

if [ "${rc}" -ne 0 ]; then
   printf '%s\n' "FAIL: --all exited rc='${rc}'" >&2
   printf '%s\n' "${out_all}" >&2
   fail=1
fi

all_required=(
   '| org-ai-assisted/msgcollector | CodeQL | warning | py/file-not-closed |'
   '| org-ai-assisted/derivative-maker | Scorecard | error | MaintainedID |'
   '| org-ai-assisted/derivative-maker | Scorecard | error | PinnedDependenciesID |'
)
for needle in "${all_required[@]}"; do
   if ! grep --quiet --fixed-strings -- "${needle}" <<< "${out_all}"; then
      printf '%s\n' "FAIL[--all]: missing fragment: ${needle}" >&2
      fail=1
   fi
done

## --- mode-flag-required check ---
rc=0
out_nomode="$(dm-github-org-security-report 2>&1)" || rc=$?
if [ "${rc}" -ne 64 ]; then
   printf '%s\n' "FAIL: missing-mode-flag run exited rc='${rc}'; expected 64 (die 64)" >&2
   fail=1
fi
if ! grep --quiet -- 'mode flag required' <<< "${out_nomode}"; then
   printf '%s\n' 'FAIL: missing-mode-flag run did not emit expected error message' >&2
   fail=1
fi

exit "${fail}"
