#!/bin/bash

## Copyright (C) 2026 - 2026 ENCRYPTED SUPPORT LLC <adrelanos@whonix.org>
## See the file COPYING for copying conditions.

## AI-Assisted

## Mock-API unit test for policy_api_call's body-capture (6th arg).
## apply_code_security_config and _policy_upsert_ruleset both rely on
## the captured body to read .id from a POST/GET response without
## re-implementing the status+warn dance. Without this test, body-
## capture is only smoke-exercised via the full apply path; here we
## pin the contract directly so a regression (e.g. the printf -v
## indirection getting refactored away) trips a clear failure here
## rather than a confusing apply-path failure later.

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

# shellcheck source=../../usr/libexec/developer-meta-files/github-org-lib.bsh
source /usr/libexec/developer-meta-files/github-org-lib.bsh
# shellcheck source=../../usr/libexec/developer-meta-files/github-policy-lib.bsh
source /usr/libexec/developer-meta-files/github-policy-lib.bsh

## policy_api_call expects these in caller scope (bash dynamic scoping).
dry_run=0
policy_warn_seen=0

## Suppress the 'ok:' log notice so test output stays focused on the
## assertion failures below; the lib emits this at the same level as
## warns, not on a separate channel.
POLICY_QUIET_OK=1

fail=0

## (1) Body-capture on 200 success populates the caller variable with
##     the response body. Fixture returns "[]\nHTTP_STATUS:200".
captured=''
if ! policy_api_call \
      'unit: list code-security configurations' \
      GET '/orgs/org-ai-assisted/code-security/configurations' \
      '' '' captured; then
   printf '%s\n' 'FAIL: policy_api_call returned non-zero on 200 success path' >&2
   fail=1
fi
if [ -z "${captured}" ]; then
   printf '%s\n' 'FAIL: captured body is empty after 200 success' >&2
   fail=1
fi
if ! printf '%s' "${captured}" | jq -e '. == []' >/dev/null 2>&1; then
   captured_q="$(printf '%q' "${captured}")"
   printf '%s\n' "FAIL: captured body did not parse as expected []: ${captured_q}" >&2
   fail=1
fi

## (2) Body-capture variable is cleared to '' on the dry-run short-
##     circuit, so callers cannot see stale state from a prior call.
dry_run=1
captured='SHOULD_BE_CLEARED'
policy_api_call 'unit: dry-run path' \
   GET '/orgs/org-ai-assisted/code-security/configurations' \
   '' '' captured >/dev/null 2>&1
if [ -n "${captured}" ]; then
   printf '%s\n' "FAIL: captured not cleared in dry-run; got '${captured}'" >&2
   fail=1
fi
dry_run=0

## (3) The 5-arg form (no body_var_name) keeps working unchanged -
##     all existing call sites (every apply path that does not need
##     to read the body) pass exactly five positional arguments.
if ! policy_api_call \
      'unit: 5-arg form, no body capture' \
      GET '/orgs/org-ai-assisted/code-security/configurations'; then
   printf '%s\n' 'FAIL: 5-arg policy_api_call returned non-zero' >&2
   fail=1
fi

## (4) policy_warn_seen must be 0 at this point - none of the calls
##     above hit a non-2xx status, so the lib must not have flipped
##     the warn flag.
if [ "${policy_warn_seen}" -ne 0 ]; then
   printf '%s\n' "FAIL: policy_warn_seen=${policy_warn_seen}; expected 0 after only-2xx calls" >&2
   fail=1
fi

## (5) On warn (non-2xx, no extra_ok match), the captured variable
##     is cleared to '' AND policy_warn_seen flips to 1. Use a path
##     whose mock fixture does not exist - ghorg_mock_dispatch returns
##     HTTP 599 which is not in the success case glob.
captured='SHOULD_BE_CLEARED_ON_WARN'
policy_warn_seen=0
if policy_api_call \
      'unit: missing-fixture warn path' \
      GET '/this/path/has/no/fixture' \
      '' '' captured >/dev/null 2>&1; then
   printf '%s\n' 'FAIL: policy_api_call returned 0 on warn path' >&2
   fail=1
fi
if [ -n "${captured}" ]; then
   printf '%s\n' "FAIL: captured not cleared on warn; got '${captured}'" >&2
   fail=1
fi
if [ "${policy_warn_seen}" -ne 1 ]; then
   printf '%s\n' "FAIL: policy_warn_seen=${policy_warn_seen} after warn; expected 1" >&2
   fail=1
fi

## (6) Body-capture variable name must be a valid bash identifier.
##     A non-identifier (e.g. with a space) flows into 'printf -v
##     "${body_var_name}"' and would fail mid-call with a confusing
##     error; the up-front check_variable_name assert in
##     policy_api_call returns non-zero before any API call fires.
##     dry_run reset above so we are back on the live path.
policy_warn_seen=0
if policy_api_call 'unit: invalid body_var_name' \
      GET '/orgs/org-ai-assisted/code-security/configurations' \
      '' '' 'has space' >/dev/null 2>&1; then
   printf '%s\n' 'FAIL: policy_api_call accepted invalid body_var_name' >&2
   fail=1
fi
## The bad-name reject path returns BEFORE the warn-flag block; this
## is intentional - the rejection is a caller-side bug, not an API
## warn. policy_warn_seen must NOT have been bumped.
if [ "${policy_warn_seen}" -ne 0 ]; then
   printf '%s\n' "FAIL: policy_warn_seen=${policy_warn_seen} after bad-name reject; expected 0" >&2
   fail=1
fi

exit "${fail}"
