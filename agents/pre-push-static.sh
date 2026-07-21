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
##   5. R-010 strict-mode block present in top 120 lines
##   6. R-011 no 'set +o errexit' toggling
##   7. R-042 no blank-line printf/log separators, and R-030/R-031
##      no bare-newline printf ('printf \n' or bare 'printf %s\n'
##      with the data arg omitted; a newline must be 'printf %s\n' "")
##   8. R-051 no inline trap command strings (use named function)
##   9. R-070 no ';;' trailing other statements on the same line
##      R-074 no ';'-chained break/continue/return (own line)
##  10. R-080 'shellcheck source=...' is a relative source-tree
##      path (no absolute /usr/..., /home/..., /dev/null)
##  11. R-081 no 'shellcheck source=/dev/null'
##  12. R-090 'has' not 'command -v' (allowlist for documented
##      bootstrap exceptions per R-093)
##  13. R-102 no 'bash' / 'sh' prepend on script invocations
##      (applies to shell + yml files)
##  14. R-120 'safe-rm' not 'rm' (with conservative carve-outs
##      for comments and known safe constructs)
##  15. R-130 No ':' as bare no-op placeholder on its own line
##      (does NOT flag the ': "${var:=default}"' parameter-default
##      idiom widely used in the codebase)
##  16. R-034 no 'echo' command (use printf); '## style-ok: allow-echo'
##  17. R-103 no process-replacement 'exec <cmd>' (fd-redirect exec
##      exempt); '## style-ok: allow-exec'
##  18. pre-commit-hooks (direct binary execution, no framework)
##      against the right file-type subsets: check-yaml,
##      check-json, check-toml, check-xml, check-ast,
##      check-added-large-files, check-merge-conflict,
##      detect-aws-credentials, detect-private-key,
##      end-of-file-fixer, trailing-whitespace-fixer, ...
##      Skipped with a note if the 'pre-commit-hooks' binaries
##      aren't on PATH (developer machines that haven't installed
##      them still get the bash-style-guide gate; CI runs in
##      debian:trixie-slim with them apt-installed).
##  19. debian/changelog is genmkfile-owned and must not be
##      hand-edited. A commit touching debian/changelog passes only
##      if it is a genmkfile auto-bump ('bumped changelog version'
##      subject, changelog-family-only diff) or carries a mandatory
##      'Changelog-manual-ok: <reason>' override trailer.
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
## Staged mode: pass '--staged' to check the staged index instead of
## a commit range (pre-commit semantics). The file LIST comes from the
## index ('git diff --cached'), but content checks read each path's
## WORKING-TREE copy -- a per-file warning is emitted when they differ
## (re-stage to check the exact blob). '--all' instead checks all
## tracked modifications vs HEAD (what 'git commit --all' records).
## '--message-file <path>' supplies the pending message so the R-001
## commit-message and changelog-trailer checks can run pre-commit;
## without it those two are skipped (push/CI still enforce them).
## '--staged' and '--per-commit' are mutually exclusive. Used by the
## Claude commit-gate hook (dist-ai-config claude/hooks/dmf-gate.py).
##
##   agents/pre-push-static.sh --staged [--all] [--message-file MSG]
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

## Mode flags. Must precede the base-ref positional.
per_commit_mode=0
staged_mode=0
staged_all=0
message_file=''
while [ "$#" -ge 1 ]; do
   case "${1}" in
      --per-commit)
         per_commit_mode=1
         shift
         ;;
      --staged)
         staged_mode=1
         shift
         ;;
      --all)
         staged_all=1
         shift
         ;;
      --message-file)
         shift
         if [ "$#" -lt 1 ]; then
            printf '%s\n' 'pre-push-static: --message-file requires an argument' >&2
            exit 2
         fi
         message_file="${1}"
         shift
         ;;
      *)
         break
         ;;
   esac
done

if [ "${staged_mode}" -eq 1 ] && [ "${per_commit_mode}" -eq 1 ]; then
   printf '%s\n' 'pre-push-static: --staged and --per-commit are mutually exclusive' >&2
   exit 2
fi
if [ "${staged_all}" -eq 1 ] && [ "${staged_mode}" -eq 0 ]; then
   printf '%s\n' 'pre-push-static: --all only applies with --staged' >&2
   exit 2
fi

if [ -n "${message_file}" ] && [ ! -f "${message_file}" ]; then
   printf '%s\n' "pre-push-static: --message-file '${message_file}' not found" >&2
   exit 2
fi
## Canonicalize to an absolute path now, at the invocation directory:
## main() cd's to the repo root before any cat/head reads the message file,
## so a relative --message-file passed from a subdirectory would otherwise
## resolve against the wrong directory after the cd.
if [ -n "${message_file}" ]; then
   message_file="$(readlink --canonicalize -- "${message_file}")" || {
      printf '%s\n' "pre-push-static: could not resolve --message-file path" >&2
      exit 2
   }
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

## Untrusted content (a flagged source line, a commit-message line) is
## emitted as-is. Terminal-safe rendering is the DISPLAY layer's job, not
## this dependency-free hook's: pipe the output through 'sanitize-string' /
## 'stcat' if you need ANSI/control-byte defanging (R-140 display sink).
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

## Emits the changed paths NUL-terminated. 'core.quotePath=false' stops git
## from C-quoting (wrapping in '"..."' with backslash escapes) paths that
## contain a tab, a byte >= 0x80, etc.; '-z' NUL-terminates so a path
## containing a newline or tab stays one record. Consumers must read with
## 'read -r -d ""' / 'mapfile -d ""'. Without this a hostile or merely
## awkward filename (e.g. $'x\ty.sh') was emitted as a quoted string that
## exists on no disk path, so every content check silently skipped it.
list_changed_files() {
   if [ "${staged_mode}" -eq 1 ]; then
      if [ "${staged_all}" -eq 1 ] && git rev-parse --verify --quiet HEAD >/dev/null; then
         git -c core.quotePath=false diff -z --name-only --diff-filter=ACMRT HEAD
      else
         git -c core.quotePath=false diff -z --name-only --diff-filter=ACMRT --cached
      fi
      return 0
   fi
   git -c core.quotePath=false diff -z --name-only --diff-filter=ACMRT "${base_ref}"...HEAD
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
   ## Match ONLY a bash/sh/dash interpreter, anchored so the shell NAME is
   ## the command (preceded by '/' as in '#!/bin/bash', or by a space as in
   ## '#!/usr/bin/env bash'), optionally followed by args. The old '*sh'
   ## glob matched any interpreter ENDING in 'sh' -- '#!/bin/zsh',
   ## '#!/usr/bin/fish' -- which then failed 'bash -n' with a spurious
   ## parse error on valid zsh/fish syntax.
   case "${first}" in
      '#!'*/bash|'#!'*/bash' '*|'#!'*' bash'|'#!'*' bash '*)
         return 0
         ;;
      '#!'*/sh|'#!'*/sh' '*|'#!'*' sh'|'#!'*' sh '*)
         return 0
         ;;
      '#!'*/dash|'#!'*/dash' '*|'#!'*' dash'|'#!'*' dash '*)
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

   if [ "${staged_mode}" -eq 1 ]; then
      if [ -z "${message_file}" ]; then
         note "staged mode: no --message-file; skipping commit-message R-001 check"
         return 0
      fi
      msg="$(cat -- "${message_file}")"
   else
      msg="$(git log "${base_ref}..HEAD" --format='%B%n')"
   fi
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

## --- Packaging-convention check: debian/changelog is genmkfile-owned ---
##
## debian/changelog must NOT be hand-edited; genmkfile auto-generates
## the version bumps (project convention: 'genmkfile
## deb-chl-bumpup-major'). A commit that modifies debian/changelog is
## accepted only when it is EITHER:
##   1. a genmkfile auto-bump commit -- subject is exactly
##      'bumped changelog version' (from 'deb-uachl-commit-changelog')
##      and it touches only changelog-family files (debian/changelog
##      and/or changelog.upstream); OR
##   2. an intentional manual edit carrying a mandatory override
##      trailer 'Changelog-manual-ok: <reason>' in its commit message.
## Any other commit touching debian/changelog FAILs the gate.
##
## Runs once over base..HEAD (independent of --per-commit), like the
## commit-message ASCII check: each commit is inspected individually so
## an auto-bump commit and a feature commit in the same range are judged
## on their own merits.
changelog_autobump_subject='bumped changelog version'

is_changelog_path() {
   case "${1}" in
      debian/changelog|*/debian/changelog)
         return 0
         ;;
   esac
   return 1
}

is_changelog_family_path() {
   case "${1}" in
      debian/changelog|*/debian/changelog|changelog.upstream|*/changelog.upstream)
         return 0
         ;;
   esac
   return 1
}

check_changelog_no_manual() {
   local sha subject body file touches_changelog only_family
   local -a changed

   while IFS= read -r sha; do
      if [ -z "${sha}" ]; then
         continue
      fi
      changed=()
      ## '-c' takes the COMBINED diff so a merge commit's own edits (an
      ## "evil merge" that hand-edits debian/changelog in the merge itself)
      ## are seen; a plain 'diff-tree -r' can emit nothing for a merge and
      ## the check would skip it. '-z' + quotePath=false keep awkward paths
      ## intact (see list_changed_files).
      mapfile -d '' -t changed < <(git -c core.quotePath=false diff-tree --no-commit-id --name-only -z -c -r "${sha}")
      if [ "${#changed[@]}" -eq 0 ]; then
         continue
      fi
      touches_changelog=0
      only_family=1
      for file in "${changed[@]}"; do
         if [ -z "${file}" ]; then
            continue
         fi
         if is_changelog_path "${file}"; then
            touches_changelog=1
         fi
         if ! is_changelog_family_path "${file}"; then
            only_family=0
         fi
      done
      if [ "${touches_changelog}" -eq 0 ]; then
         continue
      fi
      ## genmkfile auto-bump: exact subject AND changelog-family-only diff.
      subject="$(git log -1 --format=%s "${sha}")"
      if [ "${subject}" = "${changelog_autobump_subject}" ] && [ "${only_family}" -eq 1 ]; then
         continue
      fi
      ## Manual override: mandatory non-empty reason after the trailer.
      body="$(git log -1 --format=%B "${sha}")"
      if grep --quiet --ignore-case --extended-regexp \
         '^[[:space:]]*changelog-manual-ok:[[:space:]]*[^[:space:]]' <<< "${body}"; then
         continue
      fi
      fail "changelog manual-edit" "commit ${sha} edits debian/changelog (genmkfile-owned); bump via 'genmkfile deb-chl-bumpup-major', or add a 'Changelog-manual-ok: <reason>' trailer to the commit message"
   done < <(git rev-list --reverse "${base_ref}..HEAD")
}

## Staged-mode counterpart of check_changelog_no_manual: there is no
## commit yet, so judge the staged diff as a single pending commit.
## debian/changelog may be staged only as a genmkfile auto-bump
## (requires --message-file carrying the exact subject AND a
## changelog-family-only staged diff) or with a 'Changelog-manual-ok:'
## override trailer. Without a message file we cannot read the pending
## subject/trailer, so we defer to push/CI rather than fail blindly.
check_changelog_no_manual_staged() {
   local file subject body touches_changelog only_family
   local -a changed

   changed=()
   ## list_changed_files emits NUL-terminated records; read them NUL-safely
   ## (mapfile -d ''). A plain 'mapfile -t' collapses the whole NUL stream
   ## into one mangled element, so with more than one staged file the
   ## changelog paths are never recognized and a hand edit slips the gate.
   mapfile -d '' -t changed < <(list_changed_files)
   if [ "${#changed[@]}" -eq 0 ]; then
      return 0
   fi
   touches_changelog=0
   only_family=1
   for file in "${changed[@]}"; do
      if [ -z "${file}" ]; then
         continue
      fi
      if is_changelog_path "${file}"; then
         touches_changelog=1
      fi
      if ! is_changelog_family_path "${file}"; then
         only_family=0
      fi
   done
   if [ "${touches_changelog}" -eq 0 ]; then
      return 0
   fi
   if [ -z "${message_file}" ]; then
      note "staged mode: debian/changelog staged but no --message-file; deferring changelog-trailer check to push/CI"
      return 0
   fi
   subject="$(head --lines=1 -- "${message_file}")"
   if [ "${subject}" = "${changelog_autobump_subject}" ] && [ "${only_family}" -eq 1 ]; then
      return 0
   fi
   body="$(cat -- "${message_file}")"
   if grep --quiet --ignore-case --extended-regexp \
      '^[[:space:]]*changelog-manual-ok:[[:space:]]*[^[:space:]]' <<< "${body}"; then
      return 0
   fi
   fail "changelog manual-edit" "staged debian/changelog edit (genmkfile-owned); bump via 'genmkfile deb-chl-bumpup-major', or add a 'Changelog-manual-ok: <reason>' trailer to the commit message"
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
      agents/pre-push-static.sh)
         return 0
         ;;
   esac
   return 1
}

## Some scripts (including this one) carry long-form header
## docstrings before the strict-mode block; head -120 is generous
## enough to accommodate them without missing the rule's intent.
check_R010_strict_block() {
   local script header directive present
   local -a required

   required=(
      'set -o errexit'
      'set -o nounset'
      'set -o pipefail'
      'set -o errtrace'
      'shopt -s inherit_errexit'
      'shopt -s shift_verbose'
   )
   for script in "${@}"; do
      ## Count DISTINCT required directives present at column 0 (whole-line,
      ## fixed-string match), not matching LINES: six copies of
      ## 'set -o errexit' must NOT satisfy the block. head -120 accommodates
      ## the long header docstrings some scripts carry before the block.
      header="$(head --lines=120 -- "${script}")"
      present=0
      for directive in "${required[@]}"; do
         if grep --quiet --line-regexp --fixed-strings -- "${directive}" <<< "${header}"; then
            present=$((present + 1))
         fi
      done
      ## Source-able dual-mode scripts (executed AND sourced for code
      ## reuse, e.g. usr/bin/update-torbrowser sourced by
      ## dist-installer-gui; or pure helper-script .bsh libraries) MUST
      ## NOT enable strict-mode at top level: 'set -o errexit'/'nounset'
      ## and 'shopt -s inherit_errexit' would leak into the sourcing
      ## shell. Such scripts therefore keep ZERO column-0 strict lines
      ## and guard the block behind the helper-scripts
      ## was_executed()/was_sourced() runtime check (indented, invisible
      ## to the whole-line match above). Skip R-010 for exactly that shape:
      ## fully guarded (present 0) AND the guard present. A partial top-level
      ## block (present 1..5) is not a clean source-able script and stays
      ## subject to the check below. This condition also leaves this script
      ## itself enforced: it keeps all six distinct column-0 directives, so
      ## it never enters the skip despite naming the tokens.
      ## '^[^#]*' requires the guard call in CODE, not a comment: without it
      ## a mere '## TODO: add was_executed guard' would exempt a script that
      ## has no strict-mode block at all -- an unauditable bypass.
      if [ "${present}" -eq 0 ] \
         && grep --quiet --extended-regexp \
            '^[^#]*\b(was_executed|was_sourced)\b' -- "${script}"; then
         note "R-010 skipped: source-able guarded script '${script}'"
         continue
      fi
      ## Script-wide waiver: '## style-ok: no-strict' anywhere in the
      ## file. For sourced-ONLY fragments that are never executed and
      ## thus do not use the was_executed()/was_sourced() guard above:
      ## '/etc/profile.d/*.sh' login-shell fragments, '.bashrc.d'
      ## snippets, and similar. Enabling strict-mode in them would leak
      ## 'set -o errexit'/'nounset' into (and could kill) the sourcing
      ## interactive shell. Same escape-hatch shape as 'no-has'/'no-safe-rm'.
      if grep --quiet --extended-regexp \
            '^[[:space:]]*##[[:space:]]*style-ok:[[:space:]]*no-strict([[:space:]]|$)' \
            -- "${script}"; then
         note "R-010 skipped: 'style-ok: no-strict' waiver in '${script}'"
         continue
      fi
      if [ "${present}" -lt 6 ]; then
         fail "R-010 strict-mode block" "'${script}' has only ${present}/6 distinct strict-mode directives in head -120"
      fi
   done
}

check_R011_errexit_toggle() {
   local script hits
   local -a unwaived_scripts

   ## Script-wide waiver: '## style-ok: allow-errexit-toggle' anywhere in a
   ## file disables R-011 for that file (same shape as the 'no-has' /
   ## 'no-safe-rm' waivers). R-011 targets the capture-an-exit-code toggle
   ## anti-pattern; a deliberate GLOBAL mode switch is legitimate --
   ## derivative-maker 'help-steps/pre' turns errexit off so its ERR-trap
   ## exception handler can RESUME execution (auto-retry / interactive
   ## continue), which errexit makes impossible. Anchored regex (not
   ## --fixed-strings) so a typo'd superset does not silently disable the
   ## check.
   unwaived_scripts=()
   for script in "${@}"; do
      if grep --quiet --extended-regexp \
         '^[[:space:]]*##[[:space:]]*style-ok:[[:space:]]*allow-errexit-toggle([[:space:]]|$)' \
         -- "${script}"; then
         note "R-011 skipped: 'style-ok: allow-errexit-toggle' waiver in '${script}'"
         continue
      fi
      unwaived_scripts+=( "${script}" )
   done
   [ "${#unwaived_scripts[@]}" -gt 0 ] || return 0

   ## Both the long form ('set +o errexit') and the short form ('set +e',
   ## 'set +ex', 'set +xe'): '\+([a-z]*e[a-z]*)' matches a short option
   ## bundle that contains 'e'. 'set +u'/'set +o pipefail' (no errexit) do
   ## not match. Anchored at 'set', so a '## set +e' comment is spared.
   hits="$(grep --with-filename --line-number --extended-regexp '^[[:space:]]*set[[:space:]]+\+(o[[:space:]]+errexit|[a-z]*e[a-z]*)' -- "${unwaived_scripts[@]}" 2>/dev/null || true)"
   emit_hits "R-011 errexit toggle" "${hits}"
}

## Drops self-referential files (e.g., this script) from the list
## passed in; needed for R-042/R-051/R-081/R-102 whose grep
## needles appear literally in this script's own doc comments
## and/or code lines.
## Emits the kept paths NUL-terminated (not newline), so a path containing
## a newline survives the round trip; callers read with 'mapfile -d ""'.
## A newline-delimited re-emit here would undo run_file_checks's NUL-safe
## read and silently split/drop such a path from the self-filtered checks.
filter_self() {
   local f
   for f in "${@}"; do
      is_self_referential "${f}" && continue
      printf '%s\0' "${f}"
   done
}

check_R042_blank_logline() {
   local hits
   local -a fs

   mapfile -d '' -t fs < <(filter_self "${@}")
   if [ "${#fs[@]}" -eq 0 ]; then return 0; fi
   ## Bad pattern: a printf or log call that produces a blank line. The
   ## format string may be single- OR double-quoted ('printf "%s\n" ""').
   ## A redirected form ('printf %s\n "" >&2') is intentionally NOT matched
   ## here: that is the deliberate-separator case (see the keymap usage
   ## blocks), and R-030/R-031 already governs the newline spelling.
   hits="$(grep --with-filename --line-number --extended-regexp \
      "printf[[:space:]]+['\"]%s\\\\n['\"][[:space:]]+\"\"[[:space:]]*\$|log[[:space:]]+notice[[:space:]]+\"\"[[:space:]]*\$" \
      -- "${fs[@]}" 2>/dev/null || true)"
   emit_hits "R-042 blank-line separator" "${hits}"
}

check_R031_bare_newline() {
   local hits
   local -a fs

   mapfile -d '' -t fs < <(filter_self "${@}")
   if [ "${#fs[@]}" -eq 0 ]; then return 0; fi
   ## Bad pattern: a printf that emits a newline without passing the
   ## data as an explicit argument -- 'printf \n' (newline baked into
   ## the format string, R-031) or a bare 'printf %s\n' with the data
   ## argument omitted (R-030). Both must be written 'printf %s\n' "".
   ## The compliant '' data-arg form is deliberately NOT matched here
   ## (dropping a needless blank separator is R-042's separate job):
   ## the trailing group requires end-of-line or an immediately
   ## following redirect/pipe/';'/'&', or a '#' (trailing comment), so
   ## 'printf %s\n' "" (which has a following data arg) never trips it while
   ## a commented bare form ('printf %s\n' # x) still does. Covers single-
   ## and double-quoted format strings and repeated '\n'.
   ## '(^|[^-[:alnum:]])' guards the needle: find(1)'s '-printf' action
   ## ('find ... -printf '\n'' prints one newline per match, e.g. for
   ## counting with 'wc --lines') is a find flag, not the printf command,
   ## and must not be flagged.
   hits="$(grep --with-filename --line-number --extended-regexp \
      "(^|[^-[:alnum:]])printf[[:space:]]+['\"](%s)?(\\\\n)+['\"][[:space:]]*(\$|[|;&>#])" \
      -- "${fs[@]}" 2>/dev/null || true)"
   emit_hits "R-030/R-031 newline printf needs explicit \"\" arg" "${hits}"
}

check_R051_trap_inline() {
   local hits allow_regexp
   local -a fs

   mapfile -d '' -t fs < <(filter_self "${@}")
   if [ "${#fs[@]}" -eq 0 ]; then return 0; fi
   ## Bad pattern: trap followed by a single- OR double-quoted inline
   ## command string ('trap "rm -f ${t}" EXIT' as well as the single-quoted
   ## form). Named-function form is 'trap NAME SIG' (no quote). The
   ## '[^'\"]' after the opening quote requires a non-quote character
   ## inside, so 'trap "" EXIT' / 'trap '' EXIT' (clear/ignore a trap, not
   ## an inline command) are not flagged.
   hits="$(grep --with-filename --line-number --extended-regexp "\\btrap[[:space:]]+['\"][^'\"]" -- "${fs[@]}" 2>/dev/null || true)"
   ## Spare the PARAMETERIZED named-function form: bash passes a trap
   ## handler no information about the firing signal, so
   ## 'trap "handler $signal" "$signal"' is the standard idiom for
   ## signal-aware dispatch to a named function -- the rule targets inline
   ## command LOGIC, not arguments. Spared iff the quoted string is exactly
   ## one function/variable name followed by VARIABLE-EXPANSION arguments
   ## only ('$signal', '${kind}'): literal arguments keep e.g.
   ## 'trap "rm -f ${t}" EXIT' (the rule's canonical bad case) flagged.
   ## PCRE with \x27 escapes for the quotes keeps the expression
   ## shell-quoting-safe; \1 backreference matches the closing quote to
   ## the opening one.
   allow_regexp='\btrap[[:space:]]+([\x27"])[$]?[A-Za-z_][A-Za-z0-9_]*([[:space:]]+[$][{]?[A-Za-z_][A-Za-z0-9_]*[}]?)*\1'
   if [ -n "${hits}" ]; then
      hits="$(printf '%s\n' "${hits}" | grep --invert-match --perl-regexp -- "${allow_regexp}" || true)"
   fi
   emit_hits "R-051 trap inline command" "${hits}"
}

check_R070_double_semi() {
   local hits

   ## R-070: ';;' must be on its own line (optional indent + ';;' only).
   ## Flag any ';;' at end-of-line with other non-whitespace before it --
   ## spaced ('bar ;;') OR jammed ('bar;;'). A compact one-line case arm is
   ## thus always caught; the arm must be written multi-line. The leading
   ## '^[^#]*' with a non-'#' char before the ';;' excludes a ';;' that sits in
   ## a '#' comment (e.g. an illustrative '#   ;;' in documentation), mirroring
   ## how R-074 skips comment lines -- those are prose, not a real case arm.
   hits="$(grep --with-filename --line-number --extended-regexp '^[^#]*[^[:space:]#][[:space:]]*;;[[:space:]]*$' -- "${@}" 2>/dev/null || true)"
   emit_hits "R-070 ';;' on own line" "${hits}"
}

check_R074_flow_chaining() {
   local hits
   local -a fs

   ## R-074 forbids gluing a next command onto a statement with ';'. The general
   ## form is too broad to grep without false positives, but the control-flow
   ## keywords break/continue/return are the low-false-positive subset: a ';'
   ## that FOLLOWS a statement (a non-whitespace char earlier on the line, allowing
   ## spaces before the ';' so 'foo ; break' is caught too) and is FOLLOWED by one
   ## of them is almost always the chaining R-074 forbids, never bash's syntactic
   ## ';' (';;', a C-style for-loop, or the keyword on its own line). The trailing
   ## group '([[:space:];&|]|$)' enforces a real word boundary after the keyword,
   ## so a mere prefix ('x=1; return_value=1', '; continue_calls') does NOT match;
   ## the leading '^[^#]*' excludes '#'-comment lines. filter_self keeps this
   ## script's own regex/examples from self-matching.
   ##
   ## 'exit' is deliberately NOT in the set. Unlike break/continue/return it
   ## is a frequent statement separator INSIDE inline awk/sed program strings
   ## (awk '{print; exit}'), which is not bash ';'-chaining and would be a
   ## false positive; and ';'-then-exit is common in the tolerated one-liner
   ## guard idiom '|| { printf ... >&2; exit 1; }' used by self-contained
   ## bootstrap scripts. So it is not the low-false-positive subset a
   ## single-grep Tier-1 rule needs.
   mapfile -d '' -t fs < <(filter_self "${@}")
   if [ "${#fs[@]}" -eq 0 ]; then return 0; fi
   hits="$(grep --with-filename --line-number --extended-regexp \
      '^[^#]*[^#[:space:]][[:space:]]*;[[:space:]]*(break|continue|return)([[:space:];&|]|$)' -- "${fs[@]}" 2>/dev/null || true)"
   emit_hits "R-074 ';'-chained break/continue/return" "${hits}"
}

check_R081_source_devnull() {
   local hits
   local -a fs

   mapfile -d '' -t fs < <(filter_self "${@}")
   if [ "${#fs[@]}" -eq 0 ]; then return 0; fi
   hits="$(grep --with-filename --line-number 'shellcheck source=/dev/null' -- "${fs[@]}" 2>/dev/null || true)"
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
      ## Script-wide waiver: '## style-ok: no-has' anywhere in the
      ## file disables R-090 for that file. Same shape as the
      ## 'style-ok: no-safe-rm' waiver below for R-120; used by
      ## bootstrap scripts that run before helper-scripts is on the
      ## system but aren't part of the R-093 hard-coded allowlist.
      ## Anchored regex (not --fixed-strings) so a typo'd
      ## superset like 'no-has-typo' or 'no-hash' doesn't
      ## silently disable R-090.
      if grep --quiet --extended-regexp \
         '^[[:space:]]*##[[:space:]]*style-ok:[[:space:]]*no-has([[:space:]]|$)' \
         -- "${script}"; then
         continue
      fi
      ## Match 'command -v' only in CODE, not in a comment or string: the
      ## '[^#]*' prefix cannot cross a '#', so a line whose 'command -v'
      ## sits in a '##' comment (or a trailing comment, e.g. a script that
      ## documents 'use has, not command -v') is not flagged. A 'command -v'
      ## embedded in a string is a rare residual, same class as R-034/R-120.
      hits="$(grep --line-number --extended-regexp '^[[:space:]]*[^#]*command[[:space:]]+-v' -- "${script}" 2>/dev/null || true)"
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
   ##   2. 'bash foo' / 'sh foo' where the operand is a PATH: it starts with
   ##      a path character (not '-', so a flag is skipped; not '$'/'"', so a
   ##      variable is skipped) and CONTAINS a '/'. Requiring a slash is what
   ##      separates a real extensionless invocation ('bash ci/dry-run-start',
   ##      'bash ./build', 'bash /usr/bin/x') from English prose ('a bash
   ##      script', 'foo.sh as a subprocess') which has no slash. The previous
   ##      regex 2 required a literal leading '.', so a bare 'bash ci/foo'
   ##      slipped; a slash-anywhere test catches it without matching prose.
   ##
   ## The interpreter word must sit at line start or after a genuine command
   ## separator/space -- NOT a plain '\b' word boundary. '\b' also matches
   ## after '-' and '.', so a short flag ending in sh ('du -sh /path') and a
   ## script run AS the command with a path argument ('wrapper.sh /etc/x')
   ## both false-positived as an 'sh' prepend. The explicit prefix class
   ## keeps every real form: line start, 'cd x && bash y', '$(bash y)',
   ## 'true; bash y', 'timeout 5 bash y'.
   mapfile -d '' -t fs < <(filter_self "${@}")
   if [ "${#fs[@]}" -eq 0 ]; then return 0; fi
   hits="$(grep --with-filename --line-number --extended-regexp \
      '(^|[[:space:]([;&|])(bash|sh)[[:space:]]+[^-[:space:]][^[:space:]]*\.(sh|bsh|bash)\b|(^|[[:space:]([;&|])(bash|sh)[[:space:]]+[^-$"[:space:]][A-Za-z0-9._-]*/[A-Za-z0-9._/-]*(\b|$)' \
      -- "${fs[@]}" 2>/dev/null \
      | grep --invert-match --extended-regexp \
         '\b(bash|sh)[[:space:]]+-[ceilnsxv]+(\b|[[:space:]])' \
      || true)"
   emit_hits "R-102 interpreter prepend (use shebang)" "${hits}"
}

check_R120_rm() {
   local script hits line

   for script in "${@}"; do
      ## Skip this script: it carries 'rm' in fail messages and regex
      ## needles (not filesystem deletes), which the invert no longer
      ## spares now that 'safe-rm' left it.
      is_self_referential "${script}" && continue
      ## Script-wide waiver: '## style-ok: no-safe-rm' anywhere in
      ## the file disables R-120 for that file. Anchored regex (not
      ## --fixed-strings) so a typo'd superset doesn't silently
      ## disable R-120; mirrors the no-has waiver above.
      if grep --quiet --extended-regexp \
         '^[[:space:]]*##[[:space:]]*style-ok:[[:space:]]*no-safe-rm([[:space:]]|$)' \
         -- "${script}"; then
         continue
      fi
      ## 'rm' as a command word: at start-of-line, or preceded by
      ## whitespace OR a command separator (; & | (), so a separator-glued
      ## form like 'true;rm -rf x' is caught too), then followed by
      ## whitespace or end-of-line. 'safe-rm' never matches because its
      ## 'rm' is preceded by '-' (not in the class), so it is NOT in the
      ## invert below: dropping it there would have spared a whole line
      ## carrying a REAL 'rm' next to a safe-rm ('safe-rm a; rm -rf b').
      ## Comments are excluded via the '[^#]*' prefix. The invert keeps the
      ## non-filesystem-rm carve-outs (shred, git rm, git remote rm); those
      ## remain whole-line, a narrow accepted residual.
      hits="$(grep --line-number --extended-regexp \
         '^[[:space:]]*[^#]*[[:space:];&|(]rm([[:space:]]|$)|^[[:space:]]*rm([[:space:]]|$)' \
         -- "${script}" 2>/dev/null \
         | grep --invert-match --extended-regexp 'shred[[:space:]]|git[[:space:]]+(remote[[:space:]]+)?rm[[:space:]]' \
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
   hits="$(grep --with-filename --line-number --extended-regexp '^[[:space:]]*:[[:space:]]*$' -- "${@}" 2>/dev/null || true)"
   emit_hits "R-130 bare ':' no-op" "${hits}"
}

check_R034_echo() {
   local script hits line
   local -a fs

   ## R-034: 'echo' as a command (use printf). Per-script so a script-wide
   ## '## style-ok: allow-echo' waiver can exempt a file that genuinely needs it.
   ## filter_self drops this script (its own tag/comment text contains 'echo').
   mapfile -d '' -t fs < <(filter_self "${@}")
   if [ "${#fs[@]}" -eq 0 ]; then return 0; fi
   for script in "${fs[@]}"; do
      if grep --quiet --extended-regexp \
         '^[[:space:]]*##[[:space:]]*style-ok:[[:space:]]*allow-echo([[:space:]]|$)' \
         -- "${script}"; then
         continue
      fi
      ## 'echo' in COMMAND POSITION only: at line start, or immediately after
      ## a command separator (; & | && || ( ) { } backtick) or a control
      ## keyword (if/elif/while/until/then/do/else/in, whether the keyword is
      ## at line start as in 'if echo x' or mid-line as in '; then echo x').
      ## Modeled on check_R103_exec. This is the fix for the old
      ## '[[:space:]]echo' form, which matched 'echo' as a bareword anywhere
      ## after a space -- flagging it inside a string ('the echo test') or as
      ## an argument ('has echo'), neither of which runs echo as a command. A
      ## leading '#' blocks the '[^#]*' prefix, so comment lines are excluded.
      ## Residual (accepted, same as R-103): a separator inside a string
      ## ('a; echo b') still matches.
      hits="$(grep --line-number --extended-regexp \
         --regexp='^[[:space:]]*echo([[:space:]]|$)' \
         --regexp='^[[:space:]]*[^#]*[;&|(){}`][[:space:]]*echo([[:space:]]|$)' \
         --regexp='^[[:space:]]*([^#]*[[:space:]])?(then|do|else|in|if|elif|while|until)[[:space:]]+echo([[:space:]]|$)' \
         -- "${script}" 2>/dev/null || true)"
      if [ -z "${hits}" ]; then
         continue
      fi
      while IFS= read -r line; do
         fail "R-034 echo not printf" "'${script}:${line}'"
      done <<< "${hits}"
   done
}

check_R103_exec() {
   local script hits line
   local -a fs

   ## R-103: process-replacement 'exec <command>' (run as child, forward rc).
   ## Only COMMAND-POSITION 'exec' is process replacement: at line start, or right
   ## after a command separator (; & | && || ( ) { }) or a control keyword
   ## (then/do/else/in). 'exec' as an ARGUMENT to another command -- 'docker exec',
   ## 'kubectl exec', 'nsenter ... exec' -- is a bareword-preceded subcommand, NOT
   ## process replacement, so it must NOT match. fd-redirection exec ('exec 9>lock',
   ## 'exec {fd}>&-', 'exec >file') is exempt via the trailing class (a digit / '{'
   ## / '<' / '>' / '&' immediately follows 'exec'). Per-script
   ## '## style-ok: allow-exec' waiver for surfaces that must genuinely hand off the
   ## process. filter_self drops this script.
   mapfile -d '' -t fs < <(filter_self "${@}")
   if [ "${#fs[@]}" -eq 0 ]; then return 0; fi
   for script in "${fs[@]}"; do
      if grep --quiet --extended-regexp \
         '^[[:space:]]*##[[:space:]]*style-ok:[[:space:]]*allow-exec([[:space:]]|$)' \
         -- "${script}"; then
         continue
      fi
      hits="$(grep --line-number --extended-regexp \
         --regexp='^[[:space:]]*exec[[:space:]]+[^[:space:]0-9{<>&]' \
         --regexp='^[[:space:]]*[^#]*[;&|(){}][[:space:]]*exec[[:space:]]+[^[:space:]0-9{<>&]' \
         --regexp='^[[:space:]]*[^#]*[[:space:]](then|do|else|in)[[:space:]]+exec[[:space:]]+[^[:space:]0-9{<>&]' \
         -- "${script}" 2>/dev/null || true)"
      if [ -z "${hits}" ]; then
         continue
      fi
      while IFS= read -r line; do
         fail "R-103 process-replacement exec" "'${script}:${line}'"
      done <<< "${hits}"
   done
}

check_R080_shellcheck_source_path() {
   local hits

   ## R-080: a 'shellcheck source=' path must be a RELATIVE source-tree path
   ## anchored with './' or '../', i.e. it must start with '.'. This flags an
   ## absolute path ('source=/usr/...', and /dev/null), AND a bare relative
   ## name ('source=get_colors.sh' instead of './get_colors.sh') -- shellcheck
   ## resolves the bare form the same, but it breaks the codebase convention
   ## that anchors a same-directory sibling as './<file>'.
   hits="$(grep --with-filename --line-number --extended-regexp \
      '^[[:space:]]*#[[:space:]]*shellcheck[[:space:]]+source=[^.]' \
      -- "${@}" 2>/dev/null || true)"
   emit_hits "R-080 shellcheck source= must be relative (start with ./ or ../)" "${hits}"
}

is_yaml_file() {
   case "${1}" in
      *.yml|*.yaml)
         return 0
         ;;
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
   local -a flags files

   hook="${1}"
   shift
   ## Split the remaining args at '--' into leading hook flags and the
   ## trailing FILE list. Untrusted filenames MUST go after '--' so a path
   ## named like an option ('--fix=lf', '--maxkb=99999999') is a positional
   ## argument, not a flag the argparse-based hook honors (R-062). Without
   ## this a changed file could flip a fixer into rewrite mode or neuter a
   ## checker. Callers always pass '<hook> [flags...] -- <files...>'.
   flags=()
   while [ "$#" -ge 1 ] && [ "${1}" != "--" ]; do
      flags+=("${1}")
      shift
   done
   if [ "${1:-}" = "--" ]; then
      shift
   fi
   files=("${@}")
   if [ "${#files[@]}" -eq 0 ]; then
      return 0
   fi
   "${hook}" "${flags[@]}" -- "${files[@]}" \
      || fail "${hook}" "exited non-zero (hook output printed above)"
}

## Fixer hooks (end-of-file-fixer, trailing-whitespace-fixer, ...) REWRITE
## files in place. Run each against throwaway COPIES so the working tree
## (default mode) and the detached --per-commit checkout are never mutated:
## an in-place fix would silently edit the user's tree, and in --per-commit
## mode it dirties the checkout so the next 'git checkout <sha>' aborts and
## leaves a wedged detached HEAD. The non-zero exit (the hook's "would
## modify" signal) still fails the gate. Only pure file-content fixers use
## this; the git-aware hooks (check-added-large-files, ...) must see the
## real repo and stay on run_precommit_hook.
run_precommit_fixer() {
   local hook rc mirror f dir

   hook="${1}"
   shift
   if [ "$#" -eq 0 ]; then
      return 0
   fi
   mirror=""
   mirror="$(mktemp --directory)" || true
   if [ -z "${mirror}" ] || [ ! -d "${mirror}" ]; then
      fail "${hook}" "mktemp failed; cannot sandbox the fixer run"
      return 0
   fi
   for f in "${@}"; do
      dir="$(dirname -- "${f}")"
      mkdir --parents -- "${mirror}/${dir}"
      cp --no-dereference --preserve=mode -- "${f}" "${mirror}/${f}"
   done
   rc=0
   ## '--' so a filename that looks like a flag stays a positional arg (R-062).
   ( cd -- "${mirror}" && "${hook}" -- "${@}" ) || rc=$?
   ## Plain 'rm' on our own mktemp dir: this bootstrap script cannot depend
   ## on safe-rm (same deviation as the command -v use), and R-120 skips it.
   rm --recursive --force -- "${mirror}"
   if [ "${rc}" -ne 0 ]; then
      fail "${hook}" "would modify file(s) -- run '${hook}' locally and commit the result"
   fi
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
         *.yml|*.yaml)
            yaml_files+=("${f}")
            ;;
         *.json)
            json_files+=("${f}")
            ;;
         *.toml)
            toml_files+=("${f}")
            ;;
         *.xml)
            xml_files+=("${f}")
            ;;
         *.py)
            python_files+=("${f}")
            ;;
      esac
      case "${f}" in
         requirements*.txt|constraints*.txt \
         |*/requirements*.txt|*/constraints*.txt)
            req_files+=("${f}")
            ;;
      esac
   done

   ## filename-blind:
   ## '--enforce-all' so check-added-large-files inspects the files we pass
   ## instead of intersecting with 'git diff --staged' (empty at push time,
   ## which left it dead in default/union/per-commit mode).
   run_precommit_hook check-added-large-files --enforce-all -- "${@}"
   run_precommit_hook check-case-conflict     -- "${@}"
   run_precommit_hook destroyed-symlinks      -- "${@}"
   run_precommit_hook forbid-new-submodules   -- "${@}"

   ## text-only:
   run_precommit_hook check-merge-conflict    -- "${text_files[@]}"
   run_precommit_hook check-vcs-permalinks    -- "${text_files[@]}"
   run_precommit_hook detect-aws-credentials --allow-missing-credentials -- "${text_files[@]}"
   run_precommit_hook detect-private-key      -- "${text_files[@]}"
   run_precommit_fixer fix-byte-order-marker     "${text_files[@]}"
   run_precommit_fixer end-of-file-fixer         "${text_files[@]}"
   run_precommit_fixer trailing-whitespace-fixer "${text_files[@]}"
   run_precommit_hook mixed-line-ending --fix=no -- "${text_files[@]}"
   run_precommit_hook check-shebang-scripts-are-executable -- "${text_files[@]}"

   ## text AND executable:
   run_precommit_hook check-executables-have-shebangs -- "${exec_text_files[@]}"

   ## symlinks:
   run_precommit_hook check-symlinks -- "${symlink_files[@]}"

   ## type by extension:
   run_precommit_hook check-yaml             -- "${yaml_files[@]}"
   run_precommit_hook check-json             -- "${json_files[@]}"
   run_precommit_hook check-toml             -- "${toml_files[@]}"
   run_precommit_hook check-xml              -- "${xml_files[@]}"
   run_precommit_hook check-ast              -- "${python_files[@]}"
   run_precommit_hook check-builtin-literals -- "${python_files[@]}"
   run_precommit_hook debug-statement-hook   -- "${python_files[@]}"
   run_precommit_fixer double-quote-string-fixer "${python_files[@]}"
   run_precommit_fixer pretty-format-json        "${json_files[@]}"
   run_precommit_fixer requirements-txt-fixer    "${req_files[@]}"
}

## Warn (do not fail) when a checked path's working-tree content differs
## from what the current mode actually records, so a "passed" result is not
## mistaken for a check of the exact bytes. 'ref' is the diff target: empty
## for STAGED mode (working tree vs the index), 'HEAD' for UNION/push mode
## (working tree vs the pushed commit). 'hint' is the mode-specific advice.
## Both modes would otherwise pass silently on content the check never saw.
warn_worktree_skew() {
   local mode ref hint file rc

   mode="${1}"
   ref="${2}"
   hint="${3}"
   shift 3
   for file in "${@}"; do
      rc=0
      if [ -n "${ref}" ]; then
         git diff --quiet "${ref}" -- "${file}" 2>/dev/null || rc=$?
      else
         git diff --quiet -- "${file}" 2>/dev/null || rc=$?
      fi
      if [ "${rc}" -ne 0 ]; then
         note "${mode}: '${file}' ${hint}"
      fi
   done
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
   while IFS= read -r -d '' line; do
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
      check_R031_bare_newline "${shell_files[@]}"
      check_R051_trap_inline "${shell_files[@]}"
      check_R070_double_semi "${shell_files[@]}"
      check_R074_flow_chaining "${shell_files[@]}"
      check_R080_shellcheck_source_path "${shell_files[@]}"
      check_R081_source_devnull "${shell_files[@]}"
      check_R090_command_v "${shell_files[@]}"
      check_R120_rm "${shell_files[@]}"
      check_R130_null_command "${shell_files[@]}"
      check_R034_echo "${shell_files[@]}"
      check_R103_exec "${shell_files[@]}"
   else
      note "no changed shell files"
   fi

   if [ "${#shell_or_yaml[@]}" -gt 0 ]; then
      check_R102_interpreter_prepend "${shell_or_yaml[@]}"
   fi

   if [ "${#file_list[@]}" -gt 0 ]; then
      if [ "${staged_mode}" -eq 1 ] && [ "${staged_all}" -eq 0 ]; then
         warn_worktree_skew "staged mode" "" \
            "has unstaged changes; checks ran against the working tree, not the staged blob (re-stage to verify the exact committed content)" \
            "${file_list[@]}"
      fi
      if [ "${staged_mode}" -eq 0 ] && [ "${per_commit_mode}" -eq 0 ]; then
         warn_worktree_skew "push mode" "HEAD" \
            "differs between the working tree and HEAD; checks ran against the working tree, not the pushed commit (use --per-commit to check commit content exactly)" \
            "${file_list[@]}"
      fi
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
   local sha saved_base_ref toplevel

   ## Resolve everything from the repo root. list_changed_files yields
   ## repo-root-relative paths, but every content check reads them relative
   ## to the CWD. Invoked from a subdirectory (or by a hook whose CWD is not
   ## the root, e.g. the Claude commit-gate) each path would be missing and
   ## every check would silently pass. cd to the top level so the path list
   ## and the on-disk reads agree.
   toplevel="$(git rev-parse --show-toplevel 2>/dev/null)" || true
   if [ -z "${toplevel}" ]; then
      note "not inside a git repository; cannot run"
      exit 2
   fi
   cd -- "${toplevel}"

   if [ "${staged_mode}" -eq 0 ]; then
      resolve_base
   fi

   ## Commit-message R-001 check covers the whole base..HEAD range
   ## once; per-commit iteration would re-check the same messages
   ## N times. The changelog check is likewise a commit-range scan
   ## (inspects each commit's diff + message) and runs once here.
   check_ascii_commit_msg
   if [ "${staged_mode}" -eq 1 ]; then
      check_changelog_no_manual_staged
   else
      check_changelog_no_manual
   fi

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
