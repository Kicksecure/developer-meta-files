#!/bin/bash

## Copyright (C) 2026 - 2026 ENCRYPTED SUPPORT LLC <adrelanos@whonix.org>
## See the file COPYING for copying conditions.

## AI-Assisted

## Pin the wall-clock timeout on ghorg_jq. A jq program that loops
## forever ('def loop: loop; loop') must be killed within
## GHORG_JQ_TIMEOUT_SOFT + GHORG_JQ_TIMEOUT_HARD + slack, NOT run
## indefinitely.
##
## Why this matters: the timeout is the only line of defense if a
## jq parser bug produces an infinite-loop state on hostile input.
## Without the timeout (or with a broken --kill-after that cannot
## escalate SIGTERM->SIGKILL), the script would hang the CI runner
## for the full 6-hour GitHub Actions limit.

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

# shellcheck source=../../usr/libexec/developer-meta-files/github-org-lib.bsh
source /usr/libexec/developer-meta-files/github-org-lib.bsh

## Tighten the timeout for the test so a regression is caught fast.
GHORG_JQ_TIMEOUT_SOFT=1
GHORG_JQ_TIMEOUT_HARD=1

fail=0

## A jq program with an infinite recursion. timeout must terminate
## it; the elapsed wall clock is captured to also pin the bound.
start_ms="$(date +%s%N)"
rc=0
ghorg_jq -n 'def loop: loop; loop' >/dev/null 2>&1 || rc=$?
end_ms="$(date +%s%N)"
elapsed_ms=$(( (end_ms - start_ms) / 1000000 ))

## timeout exits 124 on soft-deadline-only kill, 137 on
## SIGKILL-after-kill-after. Both are valid pass states.
case "${rc}" in
   124|137) true ;;  ## ok
   0)
      printf '%s\n' "FAIL: ghorg_jq with infinite jq loop returned 0; the timeout did not fire" >&2
      fail=1
      ;;
   *)
      ## Other non-zero may mean jq itself rejected the program before
      ## entering the loop. Surface for diagnosis.
      printf '%s\n' "WARN: unexpected exit code '${rc}' from ghorg_jq; expected 124 or 137" >&2
      printf '%s\n' "(if jq rejected the program before looping, this test no longer covers the timeout path - investigate)" >&2
      fail=1
      ;;
esac

## Bound: SOFT (1s) + HARD (1s) + 2s slack for runner scheduling
## jitter and process spawn overhead. If the elapsed time is
## materially larger, --kill-after is broken or timeout is missing.
max_ms=4000
if [ "${elapsed_ms}" -gt "${max_ms}" ]; then
   printf '%s\n' "FAIL: ghorg_jq took ${elapsed_ms}ms to terminate; expected < ${max_ms}ms (SOFT=${GHORG_JQ_TIMEOUT_SOFT}s + HARD=${GHORG_JQ_TIMEOUT_HARD}s + slack)" >&2
   fail=1
fi

## Sanity: ghorg_jq with a normal hardcoded body must succeed
## quickly and produce the expected JSON.
out="$(ghorg_jq -n -- '{a: 1, b: "x"}')" || {
   printf '%s\n' "FAIL: ghorg_jq with a trivial program returned non-zero" >&2
   fail=1
}
if ! grep --quiet --fixed-strings -- '"a": 1' <<< "${out}"; then
   printf '%s\n' "FAIL: ghorg_jq trivial output did not contain the expected '\"a\": 1'" >&2
   printf '%s\n' "got: '${out}'" >&2
   fail=1
fi

exit "${fail}"
