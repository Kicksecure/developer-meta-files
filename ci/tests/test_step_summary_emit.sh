#!/bin/bash

## Copyright (C) 2026 - 2026 ENCRYPTED SUPPORT LLC <adrelanos@whonix.org>
## See the file COPYING for copying conditions.

## AI-Assisted

## Test: ci/step-summary-emit.sh emits the expected markdown shape
## when GITHUB_STEP_SUMMARY is set, and is a no-op when unset.

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
HELPER="$(cd -- "${SCRIPT_DIR}/.." && pwd)/step-summary-emit.sh"

[ -x "${HELPER}" ] || { printf '%s\n' "FAIL: helper not executable: '${HELPER}'" >&2; exit 1; }

fail=0
tmp_summary="$(mktemp)"
# shellcheck disable=SC2317  ## invoked indirectly via trap
trap_cleanup() {
   safe-rm --force -- "${tmp_summary}"
}
trap trap_cleanup RETURN

## 1. No-op when GITHUB_STEP_SUMMARY is unset.
true > "${tmp_summary}"
unset_run_output="$(unset GITHUB_STEP_SUMMARY; bash -- "${HELPER}" --tool 'noop-check' --row 'a=1' 2>&1 || true)"
if [ -n "${unset_run_output}" ]; then
   printf '%s\n' "FAIL[unset]: helper produced output when GITHUB_STEP_SUMMARY was unset: '${unset_run_output}'" >&2
   fail=1
fi
if [ -s "${tmp_summary}" ]; then
   printf '%s\n' 'FAIL[unset]: helper wrote to the would-be summary file' >&2
   fail=1
fi

## 2. Happy path: emits a heading, table, total, details link, extra block.
true > "${tmp_summary}"
GITHUB_STEP_SUMMARY="${tmp_summary}" bash -- "${HELPER}" \
   --tool 'sample (CI context)' \
   --column-header 'outcome' \
   --row 'passed=27' \
   --row 'failed=2' \
   --total 29 \
   --details-url 'https://example.invalid/run/1' \
   --extra 'Failures:|- one|- two'

required=(
   '## sample (CI context)'
   '| outcome | count |'
   '| --- | --- |'
   '| passed | 27 |'
   '| failed | 2 |'
   '**Total: 29**'
   '[Details](https://example.invalid/run/1)'
   'Failures:'
   '- one'
   '- two'
)
for needle in "${required[@]}"; do
   if ! grep --quiet --fixed-strings -- "${needle}" "${tmp_summary}"; then
      printf '%s\n' "FAIL[happy]: missing expected line: '${needle}'" >&2
      fail=1
   fi
done

## 3. Multiple invocations append rather than overwrite. The second
## call's panel heading must coexist with the first call's heading.
true > "${tmp_summary}"
GITHUB_STEP_SUMMARY="${tmp_summary}" bash -- "${HELPER}" \
   --tool 'panel-one' --row 'k=1' --total 1
GITHUB_STEP_SUMMARY="${tmp_summary}" bash -- "${HELPER}" \
   --tool 'panel-two' --row 'k=2' --total 2

if ! grep --quiet --fixed-strings -- '## panel-one' "${tmp_summary}"; then
   printf '%s\n' "FAIL[append]: first panel missing after second emit" >&2
   fail=1
fi
if ! grep --quiet --fixed-strings -- '## panel-two' "${tmp_summary}"; then
   printf '%s\n' "FAIL[append]: second panel missing" >&2
   fail=1
fi

## 4. Missing --tool exits 64.
rc=0
GITHUB_STEP_SUMMARY="${tmp_summary}" bash -- "${HELPER}" --row 'k=1' 2>/dev/null || rc=$?
if [ "${rc}" -ne 64 ]; then
   printf '%s\n' "FAIL[no-tool]: expected exit 64 for missing --tool, got '${rc}'" >&2
   fail=1
fi

## 5. Unknown flag exits 64.
rc=0
GITHUB_STEP_SUMMARY="${tmp_summary}" bash -- "${HELPER}" --tool 't' --bogus 'x' 2>/dev/null || rc=$?
if [ "${rc}" -ne 64 ]; then
   printf '%s\n' "FAIL[unknown-flag]: expected exit 64 for unknown flag, got '${rc}'" >&2
   fail=1
fi

exit "${fail}"
