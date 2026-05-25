#!/bin/bash

## Copyright (C) 2026 - 2026 ENCRYPTED SUPPORT LLC <adrelanos@whonix.org>
## See the file COPYING for copying conditions.

## AI-Assisted

## Runs every executable test_*.sh in ci/tests/. Each test is
## hermetic: GHORG_MOCK=true + GHORG_MOCK_DIR=ci/fixtures route every
## API call to a local fixture file. No network, no real tokens.
##
## A test passes if it exits 0; fails on any non-zero exit. Output is
## captured per-test and only printed on failure to keep success runs
## quiet.

## The "github-org-tools" name reflects the original scope; the
## ci/tests/ directory now also holds policy, fuzz, and workflow-yaml
## tests. Rename when a more accurate umbrella name is chosen.

set -o errexit
set -o nounset
set -o pipefail
set -o errtrace
shopt -s inherit_errexit
shopt -s shift_verbose
shopt -s nullglob

## Refuse to run outside CI. The suite is allowed to mutate the local
## /tmp directory and assumes a clean container-style environment;
## running it on a developer workstation would leave debris behind
## and might accidentally install symlinks into /usr/. CI=true is set
## by GitHub Actions and by the workflow at .github/workflows/.
if [ "${CI:-}" != "true" ]; then
   printf '%s\n' \
      'error: this script must run with CI=true (GitHub Actions or equivalent).' \
      '       Set CI=true to acknowledge before invoking.' >&2
   exit 1
fi

SCRIPT_DIR="$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" && pwd )"
TESTS_DIR="${SCRIPT_DIR}/tests"
FIXTURES_DIR="${SCRIPT_DIR}/fixtures"

if [ ! -d "${TESTS_DIR}" ]; then
  printf '%s\n' "error: tests directory missing: ${TESTS_DIR}" >&2
  exit 1
fi

## Sanity check: the lib path the tests source must exist (i.e. the
## package must be installed or the script tree present at the
## expected location).
if [ ! -r /usr/libexec/developer-meta-files/github-org-lib.bsh ]; then
  printf '%s\n' \
    'error: /usr/libexec/developer-meta-files/github-org-lib.bsh not found.' \
    '       Install developer-meta-files or symlink the source-tree files.' >&2
  exit 1
fi

# shellcheck source=../../helper-scripts/usr/libexec/helper-scripts/has.sh
source /usr/libexec/helper-scripts/has.sh

## sanitize-string is a runtime dep of github-org-lib for safe
## display. The tests use the lib's audit/error paths which call it.
has sanitize-string \
  || { printf '%s\n' 'error: sanitize-string not on PATH (helper-scripts).' >&2; exit 1; }

pass=0
fail=0
fail_names=()

for test_path in "${TESTS_DIR}"/test_*.sh; do
  test_name="$(basename -- "${test_path}")"
  printf '%s\n' "== ${test_name} =="
  log_file="$(mktemp)"
  if GHORG_MOCK_DIR="${FIXTURES_DIR}" "${test_path}" > "${log_file}" 2>&1; then
    printf '%s\n' '  PASS'
    pass=$(( pass + 1 ))
  else
    printf '%s\n' '  FAIL'
    sed -- 's/^/    | /' "${log_file}"
    fail=$(( fail + 1 ))
    fail_names+=( "${test_name}" )
  fi
  safe-rm --force -- "${log_file}"
done

printf '%s\n' "=== summary: ${pass} passed, ${fail} failed ==="
if [ "${fail}" -gt 0 ]; then
  printf '%s\n' 'failures:'
  for fname in "${fail_names[@]}"; do
    printf '%s\n' "  - ${fname}"
  done
fi

## Helper no-ops when GITHUB_STEP_SUMMARY is unset; call always.
summary_args=(
  --tool 'github-org tools (mock-API tests)'
  --column-header 'outcome'
  --row "passed=${pass}"
  --row "failed=${fail}"
  --total "$(( pass + fail ))"
)
if [ "${fail}" -gt 0 ]; then
  extra='Failures:'
  for fname in "${fail_names[@]}"; do
    extra="${extra}|- ${fname}"
  done
  summary_args+=( --extra "${extra}" )
fi
"${SCRIPT_DIR}/step-summary-emit.sh" "${summary_args[@]}"

if [ "${fail}" -gt 0 ]; then
  exit 1
fi
