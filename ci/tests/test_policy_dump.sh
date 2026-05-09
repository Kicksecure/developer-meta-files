#!/bin/bash

## Copyright (C) 2026 - 2026 ENCRYPTED SUPPORT LLC <adrelanos@whonix.org>
## See the file COPYING for copying conditions.

## AI-Assisted

## Pin --policy-dump output for both policy tools. The mode cats
## github-policy-data.bsh verbatim - no formatter to drift out of
## sync. The test asserts:
##   1. Exit code 0.
##   2. The output contains a recognizable POLICY_* readonly line so
##      a future maintainer cannot accidentally short-circuit the
##      mode to a different file or strip the data section.
##   3. No 'DRY-RUN:' / 'ok:' lines (would mean the mode also ran
##      the apply path, which would be wrong).

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

fail=0

check_dump() {
   local label out rc=0
   label="$1"; shift
   out="$("$@" 2>&1)" || rc=$?

   if [ "${rc}" -ne 0 ]; then
      printf '%s\n' "FAIL[${label}]: --policy-dump exited non-zero (rc='${rc}')" >&2
      fail=1
      return
   fi

   ## Anchor on the first SHARED constant (POLICY_FORK_PR_APPROVAL) -
   ## both tools dump the same data file, so this fragment must
   ## appear regardless of which tool was invoked.
   local anchors=(
      'readonly POLICY_FORK_PR_APPROVAL='
      'readonly POLICY_BRANCH_RULESET_BODY_ORG='
      'readonly POLICY_PERSONAL_REPO_PERSON='
      'readonly POLICY_PERSONAL_REPO_BOT='
   )
   local needle
   for needle in "${anchors[@]}"; do
      if ! grep --quiet --fixed-strings -- "${needle}" <<< "${out}"; then
         printf '%s\n' "FAIL[${label}]: missing data-file anchor: ${needle}" >&2
         fail=1
      fi
   done

   ## Negative: --policy-dump must not also fire the apply path.
   local forbidden=( 'DRY-RUN: ' 'ok: ' '[ERROR]:' )
   for needle in "${forbidden[@]}"; do
      if grep --quiet --fixed-strings -- "${needle}" <<< "${out}"; then
         printf '%s\n' "FAIL[${label}]: --policy-dump leaked an apply-path line: ${needle}" >&2
         fail=1
      fi
   done
}

check_dump 'org'      dm-github-org-policy --policy-dump
check_dump 'personal' dm-github-personal-policy --policy-dump

exit "${fail}"
