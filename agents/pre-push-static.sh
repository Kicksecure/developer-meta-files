#!/bin/bash

## Copyright (C) 2026 - 2026 ENCRYPTED SUPPORT LLC <adrelanos@whonix.org>
## See the file COPYING for copying conditions.

## AI-Assisted

## Pre-push static-checks gate. Mechanically enforces the four
## items in agents/pre-push-checklist.md "Static checks":
##   1. bash -n on every changed shell script
##   2. shellcheck --external-sources on the same set
##   3. LC_ALL=C grep -PlI '[^\x00-\x7F]' on changed files (R-001)
##   4. LC_ALL=C grep -P  '[^\x00-\x7F]' on the commit-range
##      message (R-001)
##
## Scope: files changed in HEAD vs upstream tracking branch
## (@{u}). Pass an explicit base ref as $1 to override
## (e.g. 'origin/master').
##
## Style-guide deviations, documented for reviewers:
##   * R-040 (log not printf): self-contained tool, must run on
##     a developer machine that may lack helper-scripts. Same
##     precedent as .github/actions/install-deps/install-helper-scripts.sh
##     per R-093.
##   * R-090 (has not command -v): same reason; cannot source
##     has.sh without bootstrapping the dependency check itself.
##
## Exit codes:
##   0  - all checks passed
##   1  - one or more checks failed
##   2  - environment problem (no upstream, etc.)

set -o errexit
set -o nounset
set -o pipefail
set -o errtrace
shopt -s inherit_errexit
shopt -s shift_verbose

base_ref="${1:-@{u}}"
fail_count=0

note() {
   printf '%s\n' "pre-push-static: ${1}" >&2
}

fail() {
   note "FAIL ${1}: ${2}"
   fail_count=$((fail_count + 1))
}

resolve_base() {
   local rc

   rc=0
   git rev-parse --verify --quiet "${base_ref}" >/dev/null || rc=$?
   if [ "${rc}" -ne 0 ]; then
      note "cannot resolve base ref '${base_ref}'. Pass a base, e.g. 'origin/master'."
      exit 2
   fi
}

list_changed_files() {
   git diff --name-only --diff-filter=ACMRT "${base_ref}"...HEAD
}

is_shell_file() {
   local path first

   path="${1}"
   case "${path}" in
      *.sh|*.bsh)
         return 0
         ;;
   esac
   if [ ! -f "${path}" ]; then
      return 1
   fi
   first=""
   read -r first < "${path}" || true
   case "${first}" in
      '#!'*bash*|'#!'*sh|'#!'*sh' '*)
         return 0
         ;;
   esac
   return 1
}

check_bash_n() {
   local script rc

   for script in "${@}"; do
      rc=0
      bash -n -- "${script}" || rc=$?
      if [ "${rc}" -ne 0 ]; then
         fail "bash -n" "'${script}' failed parse"
      fi
   done
}

check_shellcheck() {
   local script rc

   ## R-090 deviation: command -v used instead of has.sh; this
   ## script must be runnable as a bare git hook without
   ## helper-scripts on PATH.
   if ! command -v shellcheck >/dev/null 2>&1; then
      note "shellcheck not on PATH; skipping (apt-get install shellcheck)"
      return 0
   fi
   for script in "${@}"; do
      rc=0
      shellcheck --external-sources -- "${script}" || rc=$?
      if [ "${rc}" -ne 0 ]; then
         fail "shellcheck" "'${script}'"
      fi
   done
}

check_ascii_files() {
   local hits line

   hits="$(LC_ALL=C grep --files-with-matches --binary-files=without-match --perl-regexp '[^\x00-\x7F]' -- "${@}" || true)"
   if [ -z "${hits}" ]; then
      return 0
   fi
   while IFS= read -r line; do
      fail "R-001 ASCII" "'${line}' contains non-ASCII bytes"
   done <<< "${hits}"
}

check_ascii_commit_msg() {
   local msg hits

   msg="$(git log "${base_ref}..HEAD" --format='%B%n')"
   if [ -z "${msg}" ]; then
      return 0
   fi
   hits="$(LC_ALL=C grep --line-number --perl-regexp '[^\x00-\x7F]' <<< "${msg}" || true)"
   if [ -z "${hits}" ]; then
      return 0
   fi
   fail "R-001 ASCII" "commit-range message contains non-ASCII"
   note "offending line(s):"
   printf '%s\n' "${hits}" >&2
}

main() {
   local line
   local -a shell_files file_list

   resolve_base

   shell_files=()
   file_list=()
   while IFS= read -r line; do
      if [ -z "${line}" ]; then
         continue
      fi
      file_list+=("${line}")
      if is_shell_file "${line}"; then
         shell_files+=("${line}")
      fi
   done < <(list_changed_files)

   if [ "${#shell_files[@]}" -gt 0 ]; then
      check_bash_n "${shell_files[@]}"
      check_shellcheck "${shell_files[@]}"
   else
      note "no changed shell files"
   fi

   if [ "${#file_list[@]}" -gt 0 ]; then
      check_ascii_files "${file_list[@]}"
   fi

   check_ascii_commit_msg

   if [ "${fail_count}" -gt 0 ]; then
      note "${fail_count} check(s) failed"
      exit 1
   fi
   note "all static checks passed"
}

main "${@}"
