#!/bin/bash

## Copyright (C) 2026 - 2026 ENCRYPTED SUPPORT LLC <adrelanos@whonix.org>
## See the file COPYING for copying conditions.

## AI-Assisted

## Pin the stdin byte cap on ghorg_jq_capped. A producer that emits
## more than GHORG_JQ_MAX_BYTES bytes must NOT have all of them
## reach jq.
##
## Why this matters: if a hostile or misbehaving GitHub-API mirror
## streamed unbounded JSON, an unwrapped jq would attempt to parse
## the lot, exposing the parser to memory pressure and any
## size-dependent CVE. The 'head -c <max>' guard in front of jq
## bounds that.
##
## The test produces a bounded-size stream that is well-formed JSON
## up to GHORG_JQ_MAX_BYTES (a single big array) and asserts that
## jq sees only the prefix. Concretely: with the cap set very small
## (16 bytes) and a much larger stream offered, jq receives only
## the first 16 bytes, which is invalid JSON, so jq exits non-zero -
## proving the cap fired.

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

## --- Cap fires: 16-byte cap, 1024-byte input ---
## Set the cap small enough that only a partial JSON token reaches
## jq. The producer outputs a well-formed JSON array of 64 entries
## (~1 KB); after the cap, only the first 16 bytes survive, which
## is "[1,2,3,4,5,6,7,8" - invalid JSON, jq must error.
GHORG_JQ_MAX_BYTES=16
rc=0
out="$(yes '1,' | head -n 64 | tr -d '\n' | sed 's/,$//' | sed 's/^/[/' | sed 's/$/]/' \
   | ghorg_jq_capped -- 'length' 2>&1)" || rc=$?

if [ "${rc}" -eq 0 ]; then
   printf '%s\n' "FAIL: ghorg_jq_capped with 16-byte cap on a 1 KB input returned 0; the cap did not fire (jq saw the full input as valid JSON)" >&2
   printf '%s\n' "got: '${out}'" >&2
   fail=1
fi

## --- Cap does NOT fire on small input ---
## Same producer feeding a small payload that fits under the
## generous 4 MiB default. jq must succeed and return the array
## length. NB: 'unset GHORG_JQ_MAX_BYTES' would leave the lib's
## later 'head -c "${GHORG_JQ_MAX_BYTES}"' tripping nounset, so
## explicitly re-set to the lib default rather than unsetting.
GHORG_JQ_MAX_BYTES=4194304   ## restore default
rc=0
out="$(printf '%s' '[1,2,3,4,5]' | ghorg_jq_capped -- 'length' 2>&1)" || rc=$?

if [ "${rc}" -ne 0 ]; then
   printf '%s\n' "FAIL: ghorg_jq_capped with default 4 MiB cap on a 5-element array returned '${rc}'" >&2
   printf '%s\n' "got: '${out}'" >&2
   fail=1
fi
if [ "${out}" != '5' ]; then
   printf '%s\n' "FAIL: ghorg_jq_capped 'length' on [1,2,3,4,5] returned '${out}'; expected '5'" >&2
   fail=1
fi

exit "${fail}"
