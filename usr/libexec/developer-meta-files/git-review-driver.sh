#!/bin/bash

## Copyright (C) 2026 - 2026 ENCRYPTED SUPPORT LLC <adrelanos@whonix.org>
## See the file COPYING for copying conditions.

## AI-Assisted

## Shared hardened core for the safe git review tools (git-meld, git-kdiff3,
## git-diff-review). Sourced by a thin wrapper that first sets git_review_self
## (wrapper path), review_tool (name), and defines display_regular_file
## <old-file> <new-file> <path>.
##
## Invariant: a real change is never rendered as empty/misleading output. Classes
## a naive viewer glosses over (mode-only, symlink, gitlink spoof, Trojan-Source
## Unicode, over-long lines, driver-skipped files) are surfaced; failures are
## loud. Unicode detection is delegated to 'unicode-show'.
##
## style-ok: no-strict (sourced-only; the wrapper sets strict-mode / errexit).

: "${git_review_self:?git-review-driver.sh: wrapper must set git_review_self}"
: "${review_tool:?git-review-driver.sh: wrapper must set review_tool}"
declare -F display_regular_file >/dev/null 2>&1 \
   || { printf '%s\n' "git-review-driver.sh: wrapper must define display_regular_file()" >&2; exit 2; }

# shellcheck source=../../../../helper-scripts/usr/libexec/helper-scripts/has.sh
source "${HELPER_SCRIPTS_PATH:-}"/usr/libexec/helper-scripts/has.sh

has unicode-show

## Env var suppresses unicode-show's benign "missing newline at end" finding so
## the exit code reflects only genuinely suspicious characters.
git_review_unicode_scan() {
   local target="$1" label="$2" report rc
   rc=0
   report="$(UNICODE_SHOW_ALLOW_MISSING_FINAL_NEWLINE=1 NO_COLOR=1 unicode-show "${target}" 2>/dev/null)" || rc=$?
   if [ "${rc}" = 1 ]; then
      printf '%s\n' "${review_tool}: WARNING: ${label} suspicious Unicode (unicode-show):" >&2
      printf '%s\n' "${report}" >&2
   fi
}

## Re-dispatch mode ('git meld [<args>]' via the delegating alias).
if [ -z "${GIT_DIFF_PATH_TOTAL:-}" ]; then
   cd -- "${GIT_PREFIX:-.}" || exit 1
   ## Pre-flight without the external diff: the only way to surface files git
   ## never hands the driver (binary/-diff/diff= attrs, NUL auto-binary, LFS).
   printf '%s\n' "===== ${review_tool}: pre-flight full change set (no external diff) ====="
   git diff --no-ext-diff --stat --summary --find-renames "$@" || true
   if git diff --no-ext-diff --name-only "$@" 2>/dev/null | grep --quiet -e '\.gitattributes$'; then
      printf '%s\n' "${review_tool}: WARNING: .gitattributes changed -- can hide OTHER files' contents; review it first." >&2
   fi
   printf '%s\n' "===== ${review_tool}: per-file diffs ====="
   git -c "diff.external=${git_review_self}" diff "$@"
   exit "$?"
fi

## External diff driver mode: git passes the 7 args per changed file.
[[ -v git_external_level ]] || git_external_level=0
git_external_level=$((git_external_level + 1))
export git_external_level
if [ "${git_external_level}" -ge 3 ]; then
   exit 255
fi

## Unmerged path: git passes only the path.
if [ "$#" -lt 7 ]; then
   display_regular_file "${1}" "${1}" "${1}"
   exit 0
fi

diff_path="${1}"; old_file="${2}"; old_hex="${3}"; old_mode="${4}"
new_file="${5}"; new_hex="${6}"; new_mode="${7}"

is_submodule_blob() { grep --quiet -- '^Subproject commit' "${1}"; }
extract_commit() { sed --quiet -- 's/^Subproject commit \([0-9a-fA-F]*\).*/\1/p' "${1}"; }

for check_mode in "${old_mode}" "${new_mode}"; do
   [[ "${check_mode}" =~ ^[0-7]{6}$ ]] \
      || printf '%s\n' "${review_tool}: WARNING: unexpected mode '${check_mode}' for '${diff_path}'." >&2
done

## Control bytes in the path (cf. CVE-2025-48384, a trailing CR in a gitlink path).
path_rc=0
path_report="$(printf '%s\n' "${diff_path}" | UNICODE_SHOW_ALLOW_MISSING_FINAL_NEWLINE=1 NO_COLOR=1 unicode-show 2>/dev/null)" || path_rc=$?
if [ "${path_rc}" = 1 ]; then
   printf '%s\n' "${review_tool}: WARNING: path '${diff_path}' has suspicious/control bytes:" >&2
   printf '%s\n' "${path_report}" >&2
fi

## Mode/type change (a content diff alone would not show a mode-only change).
if [ "${old_mode}" != "${new_mode}" ]; then
   printf '%s\n' "${review_tool}: MODE CHANGE '${diff_path}': ${old_mode} -> ${new_mode}"
   case "${new_mode}" in
      100755) [ "${old_mode}" = 100755 ] || printf '%s\n' "${review_tool}: NOTE: '${diff_path}' is now EXECUTABLE (+x)." ;;
   esac
fi

## Symlink: blob content is the target; show it (meld would show it as text).
read_target() { if [ "${1}" = /dev/null ] || [ ! -e "${1}" ]; then printf '(none)'; else tr '\n' ' ' < "${1}"; fi; }
if [ "${old_mode:0:2}" = "12" ] || [ "${new_mode:0:2}" = "12" ]; then
   printf '%s\n' "${review_tool}: SYMLINK '${diff_path}': $(read_target "${old_file}") -> $(read_target "${new_file}")"
   exit 0
fi

## Submodule gitlink -- by MODE (160000), not content (content spoof otherwise).
if [ "${old_mode:0:2}" = "16" ] || [ "${new_mode:0:2}" = "16" ]; then
   old_commit="$(extract_commit "${old_file}")"; new_commit="$(extract_commit "${new_file}")"
   printf '%s\n' "Submodule ${diff_path}: ${old_commit:-<none>} -> ${new_commit:-<none>}"
   ## 'git -C' not 'cd' (an odd/symlinked path cannot redirect us); fail loud.
   if ! git -C "${diff_path}" rev-parse --git-dir >/dev/null 2>&1; then
      printf '%s\n' "${review_tool}: ERROR: submodule '${diff_path}' not an initialized git repo here; cannot show diff (init/fetch it). NOT hidden." >&2
      exit 1
   fi
   sm_rc=0
   git -C "${diff_path}" diff --no-ext-diff --find-copies --stat "${old_commit}" "${new_commit}" || sm_rc=$?
   git -C "${diff_path}" diff --no-ext-diff --find-copies "${old_commit}" "${new_commit}" || sm_rc=$?
   if [ "${sm_rc}" != 0 ]; then
      printf '%s\n' "${review_tool}: ERROR: submodule '${diff_path}' ${old_commit} -> ${new_commit}: diff unavailable (fetch it). NOT hidden." >&2
      exit 1
   fi
   exit 0
fi
if is_submodule_blob "${old_file}" || is_submodule_blob "${new_file}"; then
   printf '%s\n' "${review_tool}: WARNING: '${diff_path}' content mimics a gitlink but mode (${old_mode} -> ${new_mode}) is not 160000; treating as a regular file (possible obfuscation)." >&2
fi

git_review_unicode_scan "${new_file}" "'${diff_path}'"

## Over-long lines can truncate/hang a viewer (a place to bury a change).
longest="$(awk '{ if (length > m) m = length } END { print m + 0 }' "${new_file}" 2>/dev/null || printf '0')"
if [ "${longest}" -gt 5000 ]; then
   printf '%s\n' "${review_tool}: WARNING: '${diff_path}' has a ${longest}-char line; a viewer may truncate/hang." >&2
fi

if LC_ALL=C grep --quiet --perl-regexp '\x00' -- "${new_file}" 2>/dev/null; then
   printf '%s\n' "${review_tool}: NOTE: '${diff_path}' looks BINARY (NUL byte); --stat only." >&2
fi

git diff --no-ext-diff --find-copies --stat "${old_hex}" "${new_hex}" \
   || printf '%s\n' "${review_tool}: WARNING: '--stat' for '${diff_path}' failed; showing the diff anyway." >&2
display_regular_file "${old_file}" "${new_file}" "${diff_path}"

exit 0
