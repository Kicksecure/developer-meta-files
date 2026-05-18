#!/bin/bash

## Copyright (C) 2026 - 2026 ENCRYPTED SUPPORT LLC <adrelanos@whonix.org>
## See the file COPYING for copying conditions.

## AI-Assisted

## Stress test of ghorg_jq_capped against pathological stdin
## inputs. Asserts the wrapper contains the blast radius
## regardless of what's piped at it:
##
##   1. termination within GHORG_JQ_TIMEOUT_SOFT + _HARD + slack
##   2. byte cap (GHORG_JQ_MAX_BYTES) actually fires - jq sees only
##      the prefix when the input exceeds the cap
##   3. valid JSON within the cap parses to the expected output
##
## Inputs:
##   - 100 KB of /dev/urandom (well over the test cap; mostly
##     invalid bytes for a JSON parser)
##   - deeply-nested array '[[[[...]]]]' (parser stack-depth probe)
##   - long string key '"' + N*'a' + '"' (tokenadd-class probe;
##     CVE-2023-50268 lived in tokenadd)
##   - UTF-8 surrogate halves (jv unicode-handling probe;
##     CVE-2015-8863 was in the JSON encoder)
##
## NB: this is a stress / smoke test, not a coverage-guided
## fuzzer. AFL-on-jq lives upstream at github.com/jqlang/jq;
## this test only verifies our WRAPPER bounds the inputs jq sees
## - it does not look for new jq CVEs.

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

fail=0

## Tighten the timeout for the test so a regression hangs the
## suite for at most ~3 seconds (1+1+slack), not the production
## 2+1.
GHORG_JQ_TIMEOUT_SOFT=1
GHORG_JQ_TIMEOUT_HARD=1

## ---------------------------------------------------------------
## Case A: 100 KB of /dev/urandom with a tiny cap. Almost certainly
## invalid JSON; the wrapper must terminate quickly with non-zero
## exit (jq rejects). The point is "no hang, no panic, exits within
## the time bound."
## ---------------------------------------------------------------
GHORG_JQ_MAX_BYTES=64
start_ms="$(date +%s%N)"
rc=0
out="$(head -c 102400 /dev/urandom | ghorg_jq_capped -- '.' 2>&1 >/dev/null)" || rc=$?
end_ms="$(date +%s%N)"
elapsed_ms=$(( (end_ms - start_ms) / 1000000 ))

## Termination bound: cold-start + cap + jq parse on 64 bytes is
## sub-second; allow 3000 ms for runner GC jitter.
if [ "${elapsed_ms}" -gt 3000 ]; then
   printf '%s\n' "FAIL[urandom-cap]: took ${elapsed_ms}ms; expected <3000" >&2
   fail=1
fi
## /dev/urandom -> jq is virtually never valid JSON; rc=0 (success)
## would be remarkable - probably means jq saw an empty/truncated
## input that happens to parse as null. Either way, wrapper must
## not hang or crash with an unrelated signal. Accept rc 0 OR jq's
## parse-error rc (>0); reject anything > timeout-class (124/137).
case "${rc}" in
   124|137)
      printf '%s\n' "FAIL[urandom-cap]: timeout fired (rc=${rc}); cap should have made the input small enough to parse fast" >&2
      fail=1
      ;;
esac

## ---------------------------------------------------------------
## Case B: deeply-nested array. Hits jq's parser stack. With a
## reasonable cap, jq either parses successfully or rejects with
## a parse error (depth limit) - either is fine, as long as the
## process exits within the time bound and doesn't segfault.
## ---------------------------------------------------------------
GHORG_JQ_MAX_BYTES=4194304
depth=10000
nested_in="$(printf '[%.0s' $(seq 1 "${depth}"))$(printf ']%.0s' $(seq 1 "${depth}"))"
start_ms="$(date +%s%N)"
rc=0
printf '%s' "${nested_in}" | ghorg_jq_capped -- '.' >/dev/null 2>&1 || rc=$?
end_ms="$(date +%s%N)"
elapsed_ms=$(( (end_ms - start_ms) / 1000000 ))

if [ "${elapsed_ms}" -gt 3000 ]; then
   printf '%s\n' "FAIL[nested]: depth=${depth} took ${elapsed_ms}ms; expected <3000" >&2
   fail=1
fi
## Reject only if jq segfaulted (139=SEGV) or got SIGKILLed (137).
## Both indicate a real issue; "graceful jq parse error" is fine.
case "${rc}" in
   139|137)
      printf '%s\n' "FAIL[nested]: rc=${rc}; jq crashed or hit hard timeout on a depth='${depth}' input" >&2
      fail=1
      ;;
esac

## ---------------------------------------------------------------
## Case C: long string token. jq tokenadd-class CVEs lived here.
## Cap MUST limit what reaches the parser even if the producer
## tries to ship a 10 MB string.
## ---------------------------------------------------------------
GHORG_JQ_MAX_BYTES=1024
start_ms="$(date +%s%N)"
rc=0
printf '"' > "/tmp/long_in_$$"
head -c $((10 * 1024 * 1024)) /dev/zero | tr '\0' a >> "/tmp/long_in_$$"
printf '"' >> "/tmp/long_in_$$"
ghorg_jq_capped -- '.' < "/tmp/long_in_$$" >/dev/null 2>&1 || rc=$?
end_ms="$(date +%s%N)"
elapsed_ms=$(( (end_ms - start_ms) / 1000000 ))
safe-rm --force -- "/tmp/long_in_$$"

if [ "${elapsed_ms}" -gt 3000 ]; then
   printf '%s\n' "FAIL[longstring]: took ${elapsed_ms}ms on a 10 MB input with 1 KB cap; cap leaked or wrapper hung" >&2
   fail=1
fi
## Cap fires at 1 KB; jq sees a 1 KB unterminated string token,
## must error. rc=0 here would mean the cap didn't fire (jq
## somehow saw the closing quote 10 MB later).
if [ "${rc}" -eq 0 ]; then
   printf '%s\n' "FAIL[longstring]: rc=0; cap did not fire (jq accepted the 10 MB string)" >&2
   fail=1
fi

## ---------------------------------------------------------------
## Case D: UTF-8 surrogate halves. Real jq has had unicode-handling
## bugs (CVE-2015-8863). Wrapper must terminate without hang/crash
## regardless of what jq does internally.
## ---------------------------------------------------------------
GHORG_JQ_MAX_BYTES=4096
## "\ud800" is a high surrogate with no low partner = invalid UTF-16
## escape inside a JSON string. Most jq builds reject this with a
## parse error. Wrapper must still terminate cleanly.
surrogate_in='"\ud800"'
start_ms="$(date +%s%N)"
rc=0
printf '%s' "${surrogate_in}" | ghorg_jq_capped -- '.' >/dev/null 2>&1 || rc=$?
end_ms="$(date +%s%N)"
elapsed_ms=$(( (end_ms - start_ms) / 1000000 ))

if [ "${elapsed_ms}" -gt 3000 ]; then
   printf '%s\n' "FAIL[surrogate]: took ${elapsed_ms}ms; wrapper hung on a unicode edge case" >&2
   fail=1
fi
case "${rc}" in
   139)
      printf '%s\n' "FAIL[surrogate]: rc=139; jq segfaulted on a surrogate-half input" >&2
      fail=1
      ;;
esac

## ---------------------------------------------------------------
## Case E: positive-control. Valid JSON within cap returns the
## expected output. Confirms the wrapper's happy path is intact
## (the stress cases above pass even if the wrapper is broken in
## a way that always exits non-zero).
## ---------------------------------------------------------------
GHORG_JQ_MAX_BYTES=4194304
out="$(printf '%s' '{"foo": [1, 2, 3]}' | ghorg_jq_capped -r -- '.foo | length' 2>&1)" || {
   printf '%s\n' "FAIL[positive]: ghorg_jq_capped returned non-zero on valid JSON" >&2
   printf '%s\n' "got: ${out}" >&2
   fail=1
}
if [ "${out}" != '3' ]; then
   printf '%s\n' "FAIL[positive]: expected '3', got '${out}'" >&2
   fail=1
fi

exit "${fail}"
