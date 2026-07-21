#!/bin/bash

## Copyright (C) 2026 - 2026 ENCRYPTED SUPPORT LLC <adrelanos@whonix.org>
## See the file COPYING for copying conditions.

## AI-Assisted

## Property-style fuzz of ghorg_validate_name. Generates random
## inputs from several distributions and asserts that the validator
## accepts iff a pure-bash oracle of the documented rule set also
## accepts. Catches accidentally-permissive regex changes,
## off-by-one length-cap breakage, and missing reserved-name
## checks - any divergence between the validator and the oracle
## fails the test.
##
## Companion to test_validate_name_rejects_attacks.sh (which pins
## a fixed list of known-bad inputs). This one explores the input
## space randomly.
##
## Documented rules (from github-org-lib.bsh ghorg_validate_name):
##   - reject empty
##   - reject len > GHORG_MAX_REPO_NAME_LEN (repo) /
##                  GHORG_MAX_USER_LOGIN_LEN (user)
##   - reject if !~ ^[A-Za-z0-9._-]+$
##   - reject reserved names: '.', '..', '.git'
##   - reject leading '-'
##   - reject containing '..'

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

# shellcheck source=../../../helper-scripts/usr/libexec/helper-scripts/has.sh
source /usr/libexec/helper-scripts/has.sh
has sanitize-string \
   || { printf '%s\n' 'error: sanitize-string not on PATH' >&2; exit 1; }
# shellcheck source=../../usr/libexec/developer-meta-files/github-org-lib.bsh
source /usr/libexec/developer-meta-files/github-org-lib.bsh

## Reference oracle: returns 0 if name is valid per the rule set,
## 1 otherwise. Mirrors the production validator. Any divergence
## means either the validator or the oracle drifted.
oracle_valid() {
   local name kind max_len allowed_re
   name="$1"
   kind="${2:-repo}"
   case "${kind}" in
      user)
         max_len="${GHORG_MAX_USER_LOGIN_LEN}"
         allowed_re='^[A-Za-z0-9._-]+$'
         ;;
      ref)
         max_len="${GHORG_MAX_BRANCH_NAME_LEN}"
         allowed_re='^[A-Za-z0-9._/-]+$'
         ;;
      *)
         max_len="${GHORG_MAX_REPO_NAME_LEN}"
         allowed_re='^[A-Za-z0-9._-]+$'
         ;;
   esac
   [ -n "${name}" ] || return 1
   [ "${#name}" -le "${max_len}" ] || return 1
   [[ "${name}" =~ ${allowed_re} ]] || return 1
   case "${name}" in
      '.'|'..'|'.git')
         return 1
         ;;
      '-'*|'/'*)
         return 1
         ;;
      *'..'*|*'//'*)
         return 1
         ;;
   esac
   return 0
}

## Generate one random input drawn from one of several
## distributions. Echoes the bytes; caller passes them to the
## validator + oracle. Distributions:
##   0  short random bytes from /dev/urandom (mostly invalid charset)
##   1  random ASCII printable (mix of valid/invalid)
##   2  charset-restricted random (mostly valid, exercises length /
##                                  reserved / dot-rule edges)
##   3  edge cases (lengths near the cap, boundary lengths)
##   4  single character (every printable ASCII byte)
##
## Implementation note: 'head -c N | tr | head -c M' patterns
## SIGPIPE the producer when the trailing head closes early.
## Under pipefail (R-010) that propagates to the calling shell as
## rc=141 and errexit kills the test. To avoid that without
## disabling pipefail, read a fixed pre-sized blob, then transform
## (tr is happy because no downstream pipe), then bash-slice with
## '${var:0:N}' for the final length cut.
gen_input() {
   local kind="$1" len bytes max_len raw allowed
   case "${kind}" in
      user)
         max_len="${GHORG_MAX_USER_LOGIN_LEN}"
         allowed='A-Za-z0-9._-'
         ;;
      ref)
         max_len="${GHORG_MAX_BRANCH_NAME_LEN}"
         allowed='A-Za-z0-9._/-'
         ;;
      *)
         max_len="${GHORG_MAX_REPO_NAME_LEN}"
         allowed='A-Za-z0-9._-'
         ;;
   esac
   case "$((RANDOM % 5))" in
      0)
         len=$(( (RANDOM % max_len) + 1 ))
         raw="$(head -c "${len}" /dev/urandom | LC_ALL=C tr -d '\0\n')"
         bytes="${raw:0:${len}}"
         ;;
      1)
         len=$(( (RANDOM % max_len) + 1 ))
         raw="$(head -c $((max_len * 4)) /dev/urandom | LC_ALL=C tr -dc '\041-\176')"
         bytes="${raw:0:${len}}"
         ;;
      2)
         len=$(( (RANDOM % max_len) + 1 ))
         raw="$(head -c $((max_len * 4)) /dev/urandom | LC_ALL=C tr -dc "${allowed}")"
         bytes="${raw:0:${len}}"
         ;;
      3)
         case "$((RANDOM % 6))" in
            0)
               bytes=''
               ;;
            1)
               bytes='a'
               ;;
            2)
               bytes="$(printf 'a%.0s' $(seq 1 "${max_len}"))"
               ;;
            3)
               bytes="$(printf 'a%.0s' $(seq 1 $((max_len + 1))))"
               ;;
            4)
               bytes='.'
               ;;
            5)
               bytes='..'
               ;;
         esac
         ;;
      4)
         bytes="$(printf '\\%03o' $((33 + RANDOM % 94)))"
         bytes="$(printf '%b' "${bytes}")"
         ;;
   esac
   printf '%s' "${bytes}"
}

## Default 500 iterations balances coverage against CI wall-time.
## Each iteration's reject path calls sanitize-string (Python) via
## the validator's log helper - ~40 ms per reject. 500 iters runs
## in ~20s; 2000 iters covers more inputs but costs ~80s. Operators
## running the suite locally can boost via the env var below for a
## one-off thorough sweep.
iters="${TEST_FUZZ_VALIDATE_NAME_ITERS:-500}"
fail=0
divergences=0

for i in $(seq 1 "${iters}"); do
   ## Rotate over the three kinds to exercise each length cap and
   ## allowlist.
   case "$(( i % 3 ))" in
      0)
         kind='repo'
         ;;
      1)
         kind='user'
         ;;
      2)
         kind='ref'
         ;;
   esac

   input="$(gen_input "${kind}")"

   actual=0
   ghorg_validate_name "${input}" "${kind}" 2>/dev/null || actual=1

   expected=0
   oracle_valid "${input}" "${kind}" || expected=1

   if [ "${actual}" != "${expected}" ]; then
      divergences=$((divergences + 1))
      if [ "${divergences}" -le 5 ]; then
         input_q="$(printf '%q' "${input}")"
         printf '%s\n' "DIVERGE: kind=${kind} input=${input_q} validator=${actual} oracle=${expected}" >&2
      fi
      fail=1
   fi
done

if [ "${fail}" -ne 0 ]; then
   printf '%s\n' "FAIL: ${divergences} divergence(s) over ${iters} iterations" >&2
fi

exit "${fail}"
