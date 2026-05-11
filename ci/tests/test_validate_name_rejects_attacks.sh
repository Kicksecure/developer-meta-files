#!/bin/bash

## Copyright (C) 2026 - 2026 ENCRYPTED SUPPORT LLC <adrelanos@whonix.org>
## See the file COPYING for copying conditions.

## AI-Assisted

## Unit-style test of the name validator. Loads the lib and asserts
## that obvious bad-pattern names are rejected and good names are
## accepted. No network, no fixtures.
##
## Safety note on the "attack" inputs below: these are merely STRINGS
## passed to ghorg_validate_name, which is a pure validator (no side
## effects, no filesystem or network access). Even if the validator
## incorrectly accepted a malformed input, the test itself does
## nothing with the value beyond comparing the function's exit code.
## The validator's error path also routes input through ghorg_safe_print
## -> sanitize-string, which is purpose-built to neutralize hostile
## bytes before they reach the terminal. No actual harm is possible
## from any test input here.
##
## Depends on sanitize-string from helper-scripts being installed
## (the validator's error path calls ghorg_safe_print which invokes
## it). The CI workflow installs helper-scripts before running this
## test; locally, the script will fail loudly if sanitize-string is
## missing.

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

# shellcheck source=/usr/libexec/helper-scripts/has.sh
source /usr/libexec/helper-scripts/has.sh

has sanitize-string \
   || { printf '%s\n' \
      'error: sanitize-string not found on PATH.' \
      '       Install helper-scripts (see .github/actions/install-deps/).' >&2; exit 1; }

# shellcheck source=/usr/libexec/developer-meta-files/github-org-lib.bsh
source /usr/libexec/developer-meta-files/github-org-lib.bsh

fail=0

## Should pass. .github and .gitignore are legitimate org-meta-repo
## names that GitHub recognizes; .hidden is unusual but allowed
## under the relaxed leading-dot rule. The validator only rejects
## the three specific reserved names (., .., .git) plus leading-
## dash (arg injection) and embedded ".." (path traversal).
for valid_name in derivative-maker helper-scripts foo_bar foo.bar foo-bar1 a \
                  .github .gitignore .hidden; do
   if ! ghorg_validate_name "${valid_name}" repo 2>/dev/null; then
      printf '%s\n' "FAIL: rejected good name: ${valid_name}" >&2
      fail=1
   fi
done

## Should reject (path-traversal, control chars, shell metas,
## leading dash, embedded "..", reserved names, length overflow).
## All inputs are inert strings; the validator has no side effects.
bad_names=( '' '.git' '..' '.' '-flag' '../etc'
            'foo..bar' 'foo/bar' 'foo bar' )
for bad_name in "${bad_names[@]}"; do
   if ghorg_validate_name "${bad_name}" repo 2>/dev/null; then
      bad_name_q="$(printf '%q' "${bad_name}")"
      printf '%s\n' "FAIL: accepted bad pattern: ${bad_name_q}" >&2
      fail=1
   fi
done

## Length cap: 100 OK, 101 reject.
ok_100chars="$(printf 'a%.0s' {1..100})"
if ! ghorg_validate_name "${ok_100chars}" repo 2>/dev/null; then
   printf '%s\n' 'FAIL: rejected 100-char name' >&2
   fail=1
fi
overlong_101chars="$(printf 'a%.0s' {1..101})"
if ghorg_validate_name "${overlong_101chars}" repo 2>/dev/null; then
   printf '%s\n' 'FAIL: accepted 101-char name (over cap)' >&2
   fail=1
fi

exit "${fail}"
