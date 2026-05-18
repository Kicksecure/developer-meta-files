#!/bin/bash

## Copyright (C) 2026 - 2026 ENCRYPTED SUPPORT LLC <adrelanos@whonix.org>
## See the file COPYING for copying conditions.

## AI-Assisted

## Unit test for policy_branch_ruleset_body / policy_tag_ruleset_body
## role-keyed rules dispatch. Pins the contract that:
##
##   POLICY_RULESET_RULES_SOURCE / _PERSON  ->  3 rules including
##                                              required_signatures
##   POLICY_RULESET_RULES_MIRROR / _BOT     ->  2 rules, NO
##                                              required_signatures
##
## Rationale lives once in agents/github-policy-canonical-vs-
## mirror.md ("Summary of intentional canonical-vs-mirror splits").

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
# shellcheck source=../../usr/libexec/developer-meta-files/github-policy-lib.bsh
source /usr/libexec/developer-meta-files/github-policy-lib.bsh
# shellcheck source=../../usr/libexec/developer-meta-files/github-policy-data.bsh
source /usr/libexec/developer-meta-files/github-policy-data.bsh

fail=0

## Assert the body emitted by <factory> with <rules_var> contains the
## expected rule types AND no others. We compare the sorted unique
## .rules[].type list against an expected sorted list piped through
## the same jq filter, so output ordering and whitespace don't matter.
assert_rules() {
   local label factory rules_var expected_types
   local body actual_types

   label="$1"
   factory="$2"
   rules_var="$3"
   expected_types="$4"

   ## R-141: validate before dereferencing via ${!...}.
   check_variable_name "${rules_var}" || {
      printf '%s\n' "FAIL[${label}]: invalid rules_var '${rules_var}'" >&2
      fail=1
      return
   }
   body="$("${factory}" "test-name" repo '[]' "${!rules_var}")" || {
      printf '%s\n' "FAIL[${label}]: factory '${factory}' exited non-zero" >&2
      fail=1
      return
   }

   actual_types="$(printf '%s' "${body}" \
      | jq --raw-output -- '.rules[].type' \
      | sort \
      | tr -- '\n' ',')"
   expected_types="$(printf '%s' "${expected_types}" \
      | tr -- ',' '\n' \
      | sort \
      | tr -- '\n' ',')"

   if [ "${actual_types}" != "${expected_types}" ]; then
      printf '%s\n' "FAIL[${label}]: rule types mismatch" >&2
      printf '%s\n' "  expected: ${expected_types}" >&2
      printf '%s\n' "  actual:   ${actual_types}" >&2
      fail=1
   fi
}

## Branch ruleset, role-by-role.
assert_rules 'branch SOURCE' policy_branch_ruleset_body \
   POLICY_RULESET_RULES_SOURCE \
   'deletion,non_fast_forward,required_signatures'
assert_rules 'branch MIRROR' policy_branch_ruleset_body \
   POLICY_RULESET_RULES_MIRROR \
   'deletion,non_fast_forward'
assert_rules 'branch PERSON' policy_branch_ruleset_body \
   POLICY_RULESET_RULES_PERSON \
   'deletion,non_fast_forward,required_signatures'
assert_rules 'branch BOT' policy_branch_ruleset_body \
   POLICY_RULESET_RULES_BOT \
   'deletion,non_fast_forward'

## Tag ruleset, role-by-role. Same dispatch as branch ruleset.
assert_rules 'tag SOURCE' policy_tag_ruleset_body \
   POLICY_RULESET_RULES_SOURCE \
   'deletion,non_fast_forward,required_signatures'
assert_rules 'tag MIRROR' policy_tag_ruleset_body \
   POLICY_RULESET_RULES_MIRROR \
   'deletion,non_fast_forward'
assert_rules 'tag PERSON' policy_tag_ruleset_body \
   POLICY_RULESET_RULES_PERSON \
   'deletion,non_fast_forward,required_signatures'
assert_rules 'tag BOT' policy_tag_ruleset_body \
   POLICY_RULESET_RULES_BOT \
   'deletion,non_fast_forward'

## Default-arg path: omitting the 4th arg falls back to
## POLICY_RULESET_RULES_SOURCE (the with-required_signatures variant).
## This keeps any caller that has not been migrated to the 4-arg form
## on the safest default.
default_body="$(policy_branch_ruleset_body "test-name" repo '[]')"
default_types="$(printf '%s' "${default_body}" \
   | jq --raw-output -- '.rules[].type' \
   | sort \
   | tr -- '\n' ',')"
if [ "${default_types}" != 'deletion,non_fast_forward,required_signatures,' ]; then
   printf '%s\n' 'FAIL[default]: 3-arg call did not default to SOURCE rules' >&2
   printf '%s\n' "  actual: ${default_types}" >&2
   fail=1
fi

exit "${fail}"
