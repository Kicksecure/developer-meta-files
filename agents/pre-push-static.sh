#!/bin/bash

## Copyright (C) 2026 - 2026 ENCRYPTED SUPPORT LLC <adrelanos@whonix.org>
## See the file COPYING for copying conditions.

## AI-Assisted

## Pre-push static-checks gate. Mechanically enforces the items
## in agents/pre-push-checklist.md "Static checks" plus a tier of
## one-line-grep style-guide rules (Tier 1 in bash-style-guide
## scriptability terms):
##   1. bash -n on every changed shell script
##   2. shellcheck --external-sources on the same set (R-020,
##      R-022, R-073, R-080 et al. via shellcheck's own codes)
##   3. LC_ALL=C grep -PlI '[^\x00-\x7F]' on changed files (R-001)
##   4. LC_ALL=C grep -P  '[^\x00-\x7F]' on the commit-range
##      message (R-001)
##   5. R-010 strict-mode block present in top 30 lines
##   6. R-011 no 'set +o errexit' toggling
##   7. R-042 no blank-line printf/log separators
##   8. R-051 no inline trap command strings (use named function)
##   9. R-070 no ';;' trailing other statements on the same line
##  10a. R-080 'shellcheck source=...' is a relative source-tree
##      path (no absolute /usr/..., /home/..., /dev/null)
##  10. R-081 no 'shellcheck source=/dev/null'
##  11. R-090 'has' not 'command -v' (allowlist for documented
##      bootstrap exceptions per R-093)
##  12. R-102 no 'bash' / 'sh' prepend on script invocations
##      (applies to shell + yml files)
##  13. R-120 'safe-rm' not 'rm' (with conservative carve-outs
##      for comments and known safe constructs)
##  14. R-130 No ':' as bare no-op placeholder on its own line
##      (does NOT flag the ': "${var:=default}"' parameter-default
##      idiom widely used in the codebase)
##  15. pre-commit-hooks (direct binary execution, no framework)
##      against the right file-type subsets: check-yaml,
##      check-json, check-toml, check-xml, check-ast,
##      check-added-large-files, check-merge-conflict,
##      detect-aws-credentials, detect-private-key,
##      end-of-file-fixer, trailing-whitespace-fixer, ...
##      Skipped with a note if the 'pre-commit-hooks' binaries
##      aren't on PATH (developer machines that haven't installed
##      them still get the bash-style-guide gate; CI runs in
##      debian:trixie-slim with them apt-installed).
##
## Scope: files changed in HEAD vs upstream tracking branch
## (@{u}). Pass an explicit base ref as $1 to override
## (e.g. 'origin/master').
##
## Per-commit mode: pass '--per-commit' before the base ref to
## check each commit in <base>..HEAD individually (detached
## checkout per commit). Catches violations that existed in
## intermediate commits but were fixed before the branch tip --
## the default 'union' mode misses these because it diffs the
## merge-base against HEAD.
##
##   agents/pre-push-static.sh --per-commit origin/master
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

## Per-commit mode flag. Must precede the base-ref positional.
per_commit_mode=0
if [ "$#" -ge 1 ] && [ "${1}" = '--per-commit' ]; then
   per_commit_mode=1
   shift
fi

## Nested-brace expansion `${1:-@{u}}` mis-parses: bash terminates
## the outer expansion at the first `}`, leaving a literal `}`
## appended to the result. The no-arg case happens to reconstruct
## `@{u}` by accident; any explicit arg gets a spurious `}` glued
## on. Guard with a plain conditional instead.
##
## Hook-invocation note: when this script is wired as
## .git/hooks/pre-push, git invokes it with `$1=<remote-name>` (e.g.
## `origin`) and `$2=<remote-url>`. A bare remote name is NOT a
## resolvable base ref, so we detect that case by checking against
## `git remote` and fall back to `@{u}` (the upstream tracking
## branch, which is the right base for "what am I about to push").
if [ "$#" -ge 1 ] && [ -n "${1}" ]; then
   if git remote 2>/dev/null | grep --quiet --line-regexp --fixed-strings -- "${1}"; then
      base_ref='@{u}'
   else
      base_ref="${1}"
   fi
else
   base_ref='@{u}'
fi
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
   if [ ! -f "${path}" ]; then
      return 1
   fi
   case "${path}" in
      *.sh|*.bsh)
         return 0
         ;;
   esac
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

## --- Tier 1 style-guide checks (single-grep, near-zero false-positive) ---

emit_hits() {
   local rule_tag hits line

   rule_tag="${1}"
   hits="${2}"
   if [ -z "${hits}" ]; then
      return 0
   fi
   while IFS= read -r line; do
      fail "${rule_tag}" "${line}"
   done <<< "${hits}"
}

is_self_referential() {
   case "${1}" in
      agents/pre-push-static.sh) return 0 ;;
   esac
   return 1
}

## Some scripts (including this one) carry long-form header
## docstrings before the strict-mode block; head -100 is generous
## enough to accommodate them without missing the rule's intent.
check_R010_strict_block() {
   local script count

   for script in "${@}"; do
      count="$(head --lines=100 -- "${script}" \
         | grep --count --extended-regexp \
            '^(set -o (errexit|nounset|pipefail|errtrace)|shopt -s (inherit_errexit|shift_verbose))$' \
         || true)"
      if [ "${count}" -lt 6 ]; then
         fail "R-010 strict-mode block" "'${script}' has only ${count}/6 strict-mode lines in head -100"
      fi
   done
}

check_R011_errexit_toggle() {
   local hits

   hits="$(grep --line-number --extended-regexp '^[[:space:]]*set[[:space:]]+\+o[[:space:]]+errexit' -- "${@}" 2>/dev/null || true)"
   emit_hits "R-011 errexit toggle" "${hits}"
}

## Drops self-referential files (e.g., this script) from the list
## passed in; needed for R-042/R-051/R-081/R-102 whose grep
## needles appear literally in this script's own doc comments
## and/or code lines.
filter_self() {
   local f
   for f in "${@}"; do
      is_self_referential "${f}" && continue
      printf '%s\n' "${f}"
   done
}

check_R042_blank_logline() {
   local hits files
   local -a fs

   mapfile -t fs < <(filter_self "${@}")
   if [ "${#fs[@]}" -eq 0 ]; then return 0; fi
   ## Bad pattern: a printf or log call that produces a blank line.
   hits="$(grep --line-number --extended-regexp \
      "printf[[:space:]]+'%s\\\\n'[[:space:]]+\"\"[[:space:]]*\$|log[[:space:]]+notice[[:space:]]+\"\"[[:space:]]*\$" \
      -- "${fs[@]}" 2>/dev/null || true)"
   emit_hits "R-042 blank-line separator" "${hits}"
}

check_R051_trap_inline() {
   local hits
   local -a fs

   mapfile -t fs < <(filter_self "${@}")
   if [ "${#fs[@]}" -eq 0 ]; then return 0; fi
   ## Bad pattern: trap followed by a single-quoted inline command.
   ## Named-function form is: trap NAME SIG (no leading quote).
   hits="$(grep --line-number --extended-regexp "\\btrap[[:space:]]+'" -- "${fs[@]}" 2>/dev/null || true)"
   emit_hits "R-051 trap inline command" "${hits}"
}

check_R070_double_semi() {
   local hits

   ## ';;' preceded by a non-whitespace character on the same line.
   hits="$(grep --line-number --extended-regexp '[^[:space:]];;[[:space:]]*$' -- "${@}" 2>/dev/null || true)"
   emit_hits "R-070 ';;' on own line" "${hits}"
}

check_R081_source_devnull() {
   local hits
   local -a fs

   mapfile -t fs < <(filter_self "${@}")
   if [ "${#fs[@]}" -eq 0 ]; then return 0; fi
   hits="$(grep --line-number 'shellcheck source=/dev/null' -- "${fs[@]}" 2>/dev/null || true)"
   emit_hits "R-081 source=/dev/null" "${hits}"
}

check_R090_command_v() {
   local script hits line

   for script in "${@}"; do
      ## R-093 documented bootstrap exceptions: scripts that must
      ## run before helper-scripts/has.sh is reachable.
      case "${script}" in
         .github/actions/install-deps/install-helper-scripts.sh \
         |agents/pre-push-static.sh)
            continue
            ;;
      esac
      hits="$(grep --line-number 'command -v' -- "${script}" 2>/dev/null || true)"
      if [ -z "${hits}" ]; then
         continue
      fi
      while IFS= read -r line; do
         fail "R-090 command -v" "'${script}:${line}'"
      done <<< "${hits}"
   done
}

check_R102_interpreter_prepend() {
   local hits
   local -a fs

   ## Run on shell + yml/yaml files; .md is excluded by caller (the
   ## style guide itself self-cites the bad pattern as an example).
   ## Self-filter strips this script (whose docs cite the pattern).
   ##
   ## Two regexes:
   ##   1. 'bash foo.sh' / 'sh foo.bsh' / etc - explicit extension.
   ##   2. 'bash foo' / 'sh foo' where 'foo' doesn't look like a
   ##      flag (no leading '-') and isn't a builtin keyword that
   ##      commonly follows bash/sh in CI commands ('-c', '-e',
   ##      '-x', '-l', '-n'). Catches 'bash my-extensionless-script'
   ##      patterns that the original first regex missed.
   mapfile -t fs < <(filter_self "${@}")
   if [ "${#fs[@]}" -eq 0 ]; then return 0; fi
   hits="$(grep --line-number --extended-regexp \
      '\b(bash|sh)[[:space:]]+[^-[:space:]][^[:space:]]*\.(sh|bsh|bash)\b|\b(bash|sh)[[:space:]]+\./?[A-Za-z0-9_/-]+(\b|$)' \
      -- "${fs[@]}" 2>/dev/null \
      | grep --invert-match --extended-regexp \
         '\b(bash|sh)[[:space:]]+-[ceilnsxv]+(\b|[[:space:]])' \
      || true)"
   emit_hits "R-102 interpreter prepend (use shebang)" "${hits}"
}

check_R120_rm() {
   local script hits line

   for script in "${@}"; do
      ## Script-wide waiver: '## style-ok: no-safe-rm' anywhere in
      ## the file disables R-120 for that file.
      if grep --quiet --fixed-strings 'style-ok: no-safe-rm' -- "${script}"; then
         continue
      fi
      ## Conservative: 'rm' as a word at start-of-line or after
      ## whitespace, NOT preceded by 'safe-'. Three alternatives in
      ## the regex catch the cases:
      ##   1. 'rm' after whitespace later in the line
      ##   2. 'rm <args>' at start of line followed by whitespace
      ##   3. bare 'rm' at start of line followed by EOL (or '$')
      ## Excludes comments (lines starting with optional whitespace
      ## then '#') and the non-filesystem-rm carve-outs (safe-rm,
      ## shred, git rm, git remote rm).
      hits="$(grep --line-number --extended-regexp \
         '^[[:space:]]*[^#]*[[:space:]]rm[[:space:]]|^[[:space:]]*rm[[:space:]]|^[[:space:]]*rm$' \
         -- "${script}" 2>/dev/null \
         | grep --invert-match --extended-regexp 'safe-rm|shred[[:space:]]|git[[:space:]]+(remote[[:space:]]+)?rm[[:space:]]' \
         || true)"
      if [ -z "${hits}" ]; then
         continue
      fi
      while IFS= read -r line; do
         fail "R-120 rm not safe-rm" "'${script}:${line}'"
      done <<< "${hits}"
   done
}

check_R130_null_command() {
   local hits

   ## Bare `:` on its own line. Deliberately narrow: does NOT
   ## catch `: "${var:=default}"` (legit parameter-default idiom
   ## used in usr/libexec/.../github-org-lib.bsh) nor `: > file`
   ## (truncate) -- those have trailing content past the colon.
   hits="$(grep --line-number --extended-regexp '^[[:space:]]*:[[:space:]]*$' -- "${@}" 2>/dev/null || true)"
   emit_hits "R-130 bare ':' no-op" "${hits}"
}

check_R080_shellcheck_source_path() {
   local hits

   ## R-080: '# shellcheck source=...' directives must use a
   ## relative source-tree path. Catch absolute paths
   ## (/usr/libexec/..., /home/..., /tmp/..., etc.) and
   ## '/dev/null' (also covered by R-081 but easier to catch here).
   ## Two regex alternatives:
   ##   1. absolute path immediately after 'source='
   ##   2. literal '/dev/null'
   hits="$(grep --line-number --extended-regexp \
      '^[[:space:]]*#[[:space:]]*shellcheck[[:space:]]+source=(/[A-Za-z]|/dev/null\b)' \
      -- "${@}" 2>/dev/null || true)"
   emit_hits "R-080 shellcheck source= must be relative" "${hits}"
}

is_yaml_file() {
   case "${1}" in
      *.yml|*.yaml) return 0 ;;
   esac
   return 1
}

is_text_file() {
   ## Cheap extension match first; fall back to file --mime for
   ## files lacking a known extension (e.g. shell scripts named
   ## 'foo' with a shebang).
   local f mime
   f="${1}"
   case "${f}" in
      *.md|*.sh|*.bsh|*.bash|*.py|*.yml|*.yaml|*.json|*.toml \
      |*.xml|*.txt|*.csv|*.cfg|*.conf|*.ini|*.rst|*.html|*.css \
      |*.js|*.ts|*.c|*.h|*.cpp|*.hpp|*.go|*.rs|*.tex|*.dockerfile \
      |Dockerfile|Makefile|COPYING|README|LICENSE)
         return 0
         ;;
   esac
   if ! command -v file >/dev/null 2>&1; then
      return 1
   fi
   mime="$(file --brief --mime --dereference -- "${f}" 2>/dev/null || true)"
   case "${mime}" in
      text/* \
      |*x-shellscript* \
      |*x-python* \
      |*json* \
      |*xml* \
      |*yaml* \
      |*toml* \
      |*charset=us-ascii* \
      |*charset=utf-8*)
         return 0
         ;;
   esac
   return 1
}

## --- pre-commit-hooks integration (direct binary execution, no framework) ---
##
## Runs the curated upstream pre-commit-hooks binary set against
## the right file-type subsets, modeled on each hook's upstream
## 'types:' declaration. Probes for one representative
## (check-yaml); if absent, the whole set is skipped silently
## (developer machines without pre-commit-hooks installed still
## get the bash-style-guide gate).
##
## Hooks NOT run vs misc/pre-commit-config.yaml (with reasons):
##   no-commit-to-branch     pre-commit-stage hook; the gate
##                           runs at push (or in CI on PR/push),
##                           past the point this would matter.
##   unicode-merged-ref      stages: [pre-merge-commit, manual] only.
##   name-tests-test         dmf has no Python tests/ dir using
##                           the enforced naming convention.
##   file-contents-sorter    files: '^$' in the config (opt-in).
##   sort-simple-yaml        same.
##   fix-encoding-pragma     deprecated upstream.

run_precommit_hook() {
   local hook
   hook="${1}"
   shift
   if [ "$#" -eq 0 ]; then
      return 0
   fi
   "${hook}" "${@}" || fail "${hook}" "exited non-zero (hook output printed above)"
}

check_precommit_hooks() {
   if ! command -v check-yaml >/dev/null 2>&1; then
      note "pre-commit-hooks not on PATH; skipping (apt-get install pre-commit-hooks)"
      return 0
   fi

   local f
   local -a text_files exec_text_files symlink_files \
            yaml_files json_files toml_files xml_files \
            python_files req_files

   text_files=()
   exec_text_files=()
   symlink_files=()
   yaml_files=()
   json_files=()
   toml_files=()
   xml_files=()
   python_files=()
   req_files=()

   for f in "${@}"; do
      if [ ! -e "${f}" ]; then
         continue
      fi
      if [ -L "${f}" ]; then
         symlink_files+=("${f}")
         continue
      fi
      if is_text_file "${f}"; then
         text_files+=("${f}")
         if [ -x "${f}" ] && [ -f "${f}" ]; then
            exec_text_files+=("${f}")
         fi
      fi
      case "${f}" in
         *.yml|*.yaml) yaml_files+=("${f}") ;;
         *.json)       json_files+=("${f}") ;;
         *.toml)       toml_files+=("${f}") ;;
         *.xml)        xml_files+=("${f}") ;;
         *.py)         python_files+=("${f}") ;;
      esac
      case "${f}" in
         requirements*.txt|constraints*.txt \
         |*/requirements*.txt|*/constraints*.txt)
            req_files+=("${f}")
            ;;
      esac
   done

   ## filename-blind:
   run_precommit_hook check-added-large-files                            "${@}"
   run_precommit_hook check-case-conflict                                "${@}"
   run_precommit_hook destroyed-symlinks                                 "${@}"
   run_precommit_hook forbid-new-submodules                              "${@}"

   ## text-only:
   run_precommit_hook check-merge-conflict                               "${text_files[@]}"
   run_precommit_hook check-vcs-permalinks                               "${text_files[@]}"
   run_precommit_hook detect-aws-credentials --allow-missing-credentials "${text_files[@]}"
   run_precommit_hook detect-private-key                                 "${text_files[@]}"
   run_precommit_hook fix-byte-order-marker                              "${text_files[@]}"
   run_precommit_hook end-of-file-fixer                                  "${text_files[@]}"
   run_precommit_hook trailing-whitespace-fixer                          "${text_files[@]}"
   run_precommit_hook mixed-line-ending --fix=no                         "${text_files[@]}"
   run_precommit_hook check-shebang-scripts-are-executable               "${text_files[@]}"

   ## text AND executable:
   run_precommit_hook check-executables-have-shebangs                    "${exec_text_files[@]}"

   ## symlinks:
   run_precommit_hook check-symlinks                                     "${symlink_files[@]}"

   ## type by extension:
   run_precommit_hook check-yaml                "${yaml_files[@]}"
   run_precommit_hook check-json                "${json_files[@]}"
   run_precommit_hook check-toml                "${toml_files[@]}"
   run_precommit_hook check-xml                 "${xml_files[@]}"
   run_precommit_hook check-ast                 "${python_files[@]}"
   run_precommit_hook check-builtin-literals    "${python_files[@]}"
   run_precommit_hook debug-statement-hook      "${python_files[@]}"
   run_precommit_hook double-quote-string-fixer "${python_files[@]}"
   run_precommit_hook pretty-format-json        "${json_files[@]}"
   run_precommit_hook requirements-txt-fixer    "${req_files[@]}"
}

run_file_checks() {
   ## Run all file-content checks given the current global
   ## base_ref. Caller controls base_ref (single union pass in
   ## default mode; per-commit loop in --per-commit mode).
   local line
   local -a shell_files yaml_files shell_or_yaml file_list

   shell_files=()
   yaml_files=()
   shell_or_yaml=()
   file_list=()
   while IFS= read -r line; do
      if [ -z "${line}" ]; then
         continue
      fi
      file_list+=("${line}")
      if is_shell_file "${line}"; then
         shell_files+=("${line}")
         shell_or_yaml+=("${line}")
      elif is_yaml_file "${line}"; then
         yaml_files+=("${line}")
         shell_or_yaml+=("${line}")
      fi
   done < <(list_changed_files)

   if [ "${#shell_files[@]}" -gt 0 ]; then
      check_bash_n "${shell_files[@]}"
      check_shellcheck "${shell_files[@]}"
      check_R010_strict_block "${shell_files[@]}"
      check_R011_errexit_toggle "${shell_files[@]}"
      check_R042_blank_logline "${shell_files[@]}"
      check_R051_trap_inline "${shell_files[@]}"
      check_R070_double_semi "${shell_files[@]}"
      check_R080_shellcheck_source_path "${shell_files[@]}"
      check_R081_source_devnull "${shell_files[@]}"
      check_R090_command_v "${shell_files[@]}"
      check_R120_rm "${shell_files[@]}"
      check_R130_null_command "${shell_files[@]}"
   else
      note "no changed shell files"
   fi

   if [ "${#shell_or_yaml[@]}" -gt 0 ]; then
      check_R102_interpreter_prepend "${shell_or_yaml[@]}"
   fi

   if [ "${#file_list[@]}" -gt 0 ]; then
      check_ascii_files "${file_list[@]}"
      check_precommit_hooks "${file_list[@]}"
   fi
}

restore_head_ref=""

restore_head() {
   if [ -n "${restore_head_ref}" ]; then
      git checkout --quiet "${restore_head_ref}" 2>/dev/null || true
   fi
}

main() {
   local sha saved_base_ref

   resolve_base

   ## Commit-message R-001 check covers the whole base..HEAD range
   ## once; per-commit iteration would re-check the same messages
   ## N times.
   check_ascii_commit_msg

   if [ "${per_commit_mode}" -eq 1 ]; then
      ## Detached-checkout iteration. Capture the current ref so
      ## the trap can restore the working tree even on failure.
      restore_head_ref="$(git symbolic-ref --quiet --short HEAD \
         || git rev-parse HEAD)"
      trap restore_head EXIT
      saved_base_ref="${base_ref}"
      while IFS= read -r sha; do
         if [ -z "${sha}" ]; then
            continue
         fi
         note "per-commit: ${sha}"
         git checkout --quiet "${sha}"
         base_ref="${sha}^"
         run_file_checks
      done < <(git rev-list --reverse "${saved_base_ref}..HEAD")
      base_ref="${saved_base_ref}"
   else
      run_file_checks
   fi

   if [ "${fail_count}" -gt 0 ]; then
      note "${fail_count} check(s) failed"
      exit 1
   fi
   note "all static checks passed"
}

main "${@}"
