#!/bin/bash

## Copyright (C) 2026 - 2026 ENCRYPTED SUPPORT LLC <adrelanos@whonix.org>
## See the file COPYING for copying conditions.

## AI-Assisted

## Unit-style test of ghorg_compute_backoff_seconds and the
## rate-limit-wait header parser. Network-free; loads the lib and
## calls the helpers directly with crafted inputs.

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
expect() {
  local desc want got want_q got_q

  desc="$1"
  want="$2"
  got="$3"

  if [ "${got}" != "${want}" ]; then
    want_q="$(printf '%q' "${want}")"
    got_q="$(printf '%q' "${got}")"
    printf '%s\n' "FAIL: ${desc}: want '${want_q}' got '${got_q}'" >&2
    fail=1
  fi
}

## Backoff doubles per attempt up to GHORG_MAX_BACKOFF_SECONDS.
expect 'backoff[0]' '30'   "$(ghorg_compute_backoff_seconds 0)"
expect 'backoff[1]' '60'   "$(ghorg_compute_backoff_seconds 1)"
expect 'backoff[2]' '120'  "$(ghorg_compute_backoff_seconds 2)"
expect 'backoff[3]' '240'  "$(ghorg_compute_backoff_seconds 3)"

## Retry-After header takes precedence.
hdr="$(mktemp)"

test_rate_limit_retry_cleanup_hdr() {
   # shellcheck disable=SC2317  ## invoked indirectly via trap
   safe-rm --force -- "${hdr}"
}
trap test_rate_limit_retry_cleanup_hdr EXIT
printf '%s\r\n' \
  'HTTP/2 429' \
  'Retry-After: 17' \
  'X-RateLimit-Reset: 99999999999' \
  '' > "${hdr}"
parsed_retry_after="$(ghorg_parse_rate_limit_wait "${hdr}")"
expect 'parse Retry-After' '17' "${parsed_retry_after}"

## X-RateLimit-Reset used as fallback. Check just that we get a
## non-empty positive integer for a reset 10 seconds in the future.
now_seconds="$(date -u +%s)"
future=$(( now_seconds + 10 ))
printf '%s\r\n' \
  'HTTP/2 403' \
  'X-RateLimit-Remaining: 0' \
  "X-RateLimit-Reset: ${future}" \
  '' > "${hdr}"
got="$(ghorg_parse_rate_limit_wait "${hdr}")"
if [ -z "${got}" ] || ! [[ "${got}" =~ ^[0-9]+$ ]]; then
  got_q="$(printf '%q' "${got}")"
  printf '%s\n' "FAIL: parse X-RateLimit-Reset: got '${got_q}'" >&2
  fail=1
fi

## Reset already in the past -> empty stdout + non-zero exit (caller
## falls back to backoff via 'if ! wait="$(...)"').
now_seconds="$(date -u +%s)"
past=$(( now_seconds - 100 ))
printf '%s\r\n' \
  'HTTP/2 403' \
  "X-RateLimit-Reset: ${past}" \
  '' > "${hdr}"
parsed_stale=''
ghorg_parse_rate_limit_wait_rc=0
parsed_stale="$(ghorg_parse_rate_limit_wait "${hdr}")" \
  || ghorg_parse_rate_limit_wait_rc=$?
expect 'parse stale reset stdout' '' "${parsed_stale}"
expect 'parse stale reset exit'   '1' "${ghorg_parse_rate_limit_wait_rc}"

## No relevant header -> empty stdout + non-zero exit.
printf '%s\r\n' \
  'HTTP/2 200' \
  'Server: github.com' \
  '' > "${hdr}"
parsed_no_hdr=''
ghorg_parse_rate_limit_wait_rc=0
parsed_no_hdr="$(ghorg_parse_rate_limit_wait "${hdr}")" \
  || ghorg_parse_rate_limit_wait_rc=$?
expect 'parse no rate-limit hdr stdout' '' "${parsed_no_hdr}"
expect 'parse no rate-limit hdr exit'   '1' "${ghorg_parse_rate_limit_wait_rc}"

exit "${fail}"
