#!/bin/bash

## Copyright (C) 2026 - 2026 ENCRYPTED SUPPORT LLC <adrelanos@whonix.org>
## See the file COPYING for copying conditions.

## AI-Assisted

## Regression tests for the safe git review tools (git-diff-review,
## git-review-difftool, git-review-mergetool and their shared core). These
## exercise the NON-interactive, non-GUI behaviour that CI can assert
## deterministically:
##
##   * git-review-difftool / -mergetool must not abort with an unbound-variable
##     error after scanning (they once referenced a removed 'git_review_fatal').
##   * git-diff-review must not report a false "stcat failed" for a plain changed
##     file ('diff' rc 1 = "files differ" must not leak into the stcat check).
##   * undecodable / non-UTF-8 content must FAIL CLOSED when there is no terminal
##     to prompt on (the interactive continue only proceeds on an explicit yes).
##
## The interactive "continue past flagged content" prompt needs a real /dev/tty
## and is verified separately with a pty harness; it is out of scope here.
##
## The tools hard-code '/usr/libexec/developer-meta-files/...' for their own
## sourced libs, so this test STAGES the in-tree copies into a temp prefix with
## that path rewritten. It therefore tests the source tree under review rather
## than a possibly-stale installed package. The helper-scripts .sh libraries are
## resolved via HELPER_SCRIPTS_PATH (sibling checkout if present, else the
## installed /usr copy); the helper binaries (stcat, unicode-show, ...) come
## from PATH.

set -o errexit
set -o nounset
set -o pipefail
set -o errtrace
shopt -s inherit_errexit
shopt -s shift_verbose

SCRIPT_DIR="$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" && pwd )"
REPO_ROOT="$( cd -- "${SCRIPT_DIR}/../.." && pwd )"

## helper-scripts .sh libs: prefer a sibling source checkout, fall back to the
## installed copy (empty HELPER_SCRIPTS_PATH resolves to /usr/libexec/...).
sibling_hs="$( cd -- "${REPO_ROOT}/../helper-scripts" 2>/dev/null && pwd || true )"
if [ -n "${sibling_hs}" ] && [ -e "${sibling_hs}/usr/libexec/helper-scripts/has.sh" ]; then
   export HELPER_SCRIPTS_PATH="${sibling_hs}"
else
   export HELPER_SCRIPTS_PATH=""
fi

stage="$(mktemp --directory --tmpdir git-review-tools-test.XXXXXX)"

## Trap target (invoked indirectly via 'trap ... EXIT', not dead code).
# shellcheck disable=SC2317
cleanup() {
   safe-rm --recursive --force -- "${stage}"
}
trap cleanup EXIT

mkdir -p -- "${stage}/bin" "${stage}/lib"
for tool in git-diff-review git-review-difftool git-review-mergetool; do
   sed "s#/usr/libexec/developer-meta-files/#${stage}/lib/#g" \
      -- "${REPO_ROOT}/usr/bin/${tool}" > "${stage}/bin/${tool}"
   chmod +x -- "${stage}/bin/${tool}"
done
review_libs=(
   git-review-driver.sh
   git-review-scan.sh
)
for lib in "${review_libs[@]}"; do
   sed "s#/usr/libexec/developer-meta-files/#${stage}/lib/#g" \
      -- "${REPO_ROOT}/usr/libexec/developer-meta-files/${lib}" > "${stage}/lib/${lib}"
done
export PATH="${stage}/bin:${PATH}"

fail=0

report_fail() {
   printf '%s\n' "FAIL: ${1}" >&2
   fail=1
}

## 1. git-review-difftool on two harmless files must render and exit 0. Before
##    the fix this aborted with 'git_review_fatal: unbound variable' under
##    'set -o nounset' for every non-fatal file.
printf 'alpha\nbeta\n'    > "${stage}/a"
printf 'alpha\ngamma\n'   > "${stage}/b"
rc=0
timeout 30 git-review-difftool diff-review "${stage}/a" "${stage}/b" >/dev/null 2>&1 || rc=$?
if [ "${rc}" -ne 0 ]; then
   report_fail "git-review-difftool diff-review on harmless files exited non-zero (rc='${rc}')"
fi

## 2. Wrong argument count must fail with a usage message and exit 2.
rc=0
out="$(timeout 30 git-review-difftool only-one-arg 2>&1)" || rc=$?
if [ "${rc}" -ne 2 ]; then
   report_fail "git-review-difftool with one arg exited '${rc}', expected 2"
fi
if ! grep --quiet --fixed-strings -- 'usage: git-review-difftool' <<< "${out}"; then
   report_fail "git-review-difftool arg-count error is missing the usage line"
fi

## 3. git-review-mergetool with a binary conflict side must refuse and exit 1
##    (no GUI), proving the scan-then-refuse path runs without the crash.
printf 'base\n'            > "${stage}/mb"
printf 'local\n\x00nul\n' > "${stage}/ml"
printf 'remote\n'         > "${stage}/mr"
printf 'merged\n'         > "${stage}/mm"
rc=0
out="$(timeout 30 git-review-mergetool meld "${stage}/mb" "${stage}/ml" "${stage}/mr" "${stage}/mm" 2>&1)" || rc=$?
if [ "${rc}" -ne 1 ]; then
   report_fail "git-review-mergetool with a binary side exited '${rc}', expected 1"
fi
if ! grep --quiet --fixed-strings -- 'looks BINARY' <<< "${out}"; then
   report_fail "git-review-mergetool binary-side refusal message is missing"
fi

## The remaining tests drive git-diff-review as a real external-diff driver.
repo="$(mktemp --directory --tmpdir git-review-repo.XXXXXX)"
git -C "${repo}" init --quiet
git -C "${repo}" config user.email 'test@example.com'
git -C "${repo}" config user.name 'test'

## 4. A plain changed file must exit 0 with NO "stcat failed" line. That line
##    used to fire for every changed file because 'diff' rc 1 ("files differ")
##    leaked into the stcat exit-code check.
printf 'one\ntwo\n' > "${repo}/clean.txt"
git -C "${repo}" add clean.txt
git -C "${repo}" commit --quiet -m 'add clean'
printf 'one\nTWO changed\n' > "${repo}/clean.txt"
rc=0
out="$(cd -- "${repo}" && timeout 30 git-diff-review 2>&1)" || rc=$?
if [ "${rc}" -ne 0 ]; then
   report_fail "git-diff-review on a plain changed file exited '${rc}', expected 0"
fi
if grep --quiet --fixed-strings -- 'stcat failed' <<< "${out}"; then
   report_fail "git-diff-review reported a false 'stcat failed' for a plain changed file"
fi

## 5. Undecodable / non-UTF-8 content with no controlling terminal must FAIL
##    CLOSED (non-zero), and must not hang or spew /dev/tty open errors. 'setsid'
##    detaches the controlling terminal so the interactive prompt cannot be
##    reached; 'timeout' guards against a regression that blocks on a read.
printf 'harmless\n' > "${repo}/bad.txt"
git -C "${repo}" add bad.txt
git -C "${repo}" commit --quiet -m 'add bad'
printf 'lead \xff\xfe trail\n' > "${repo}/bad.txt"
rc=0
out="$(cd -- "${repo}" && setsid --wait timeout 30 git-diff-review 2>&1)" || rc=$?
if [ "${rc}" -eq 0 ]; then
   report_fail "git-diff-review passed undecodable content with no terminal (must fail closed)"
fi
if [ "${rc}" -eq 124 ]; then
   report_fail "git-diff-review hung on undecodable content with no terminal (timeout)"
fi
if ! grep --quiet --fixed-strings -- 'Failing closed' <<< "${out}"; then
   report_fail "git-diff-review fatal path is missing the 'Failing closed' message"
fi

safe-rm --recursive --force -- "${repo}"

exit "${fail}"
