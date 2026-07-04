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

[ -n "${git_review_self:-}" ] \
   || { printf '%s\n' "git-review-driver.sh: wrapper must set 'git_review_self'" >&2; exit 2; }
[ -n "${review_tool:-}" ] \
   || { printf '%s\n' "git-review-driver.sh: wrapper must set 'review_tool'" >&2; exit 2; }
declare -F display_regular_file >/dev/null 2>&1 \
   || { printf '%s\n' "git-review-driver.sh: wrapper must define 'display_regular_file()'" >&2; exit 2; }

## Shared content-hardening core (has-checks, the fatal flag, Unicode/Trojan-
## Source surfacing via git_review_unicode_scan, fail-closed git_review_finish,
## git_review_cleanup, and git_review_scan_content for the wrappers). Single-
## sourced so every review contract -- external diff here, difftool/mergetool in
## the wrappers -- behaves identically.
# shellcheck source=git-review-scan.sh
source /usr/libexec/developer-meta-files/git-review-scan.sh

## Re-dispatch mode ('git meld [<args>]' via the delegating alias).
if [ -z "${GIT_DIFF_PATH_TOTAL:-}" ]; then
   cd -- "${GIT_PREFIX:-.}" || exit 1
   ## Shared status file: per-file external-diff runs append here (only when
   ## GIT_REVIEW_UNICODE_NONFATAL is set); a non-empty file means fail at the end.
   git_review_status_file="$(mktemp --tmpdir git-review-status.XXXXXX)"
   export git_review_status_file
   trap git_review_cleanup EXIT
   ## Pre-flight without the external diff: the only way to surface files git
   ## never hands the driver (binary/-diff/diff= attrs, NUL auto-binary, LFS).
   printf '%s\n' "===== ${review_tool}: pre-flight full change set (no external diff) ====="
   git diff --no-ext-diff --stat --summary --find-renames "$@" || true
   ## Capture the name list FIRST: piping git straight into grep would, under
   ## pipefail, let a git failure mask a real match and drop this warning -- the
   ## one file the tool most wants to flag.
   changed_names="$(git diff --no-ext-diff --name-only "$@" 2>/dev/null || true)"
   if printf '%s\n' "${changed_names}" | grep --quiet -e '\.gitattributes$'; then
      printf '%s\n' "${review_tool}: WARNING: '.gitattributes' changed -- can hide OTHER files' contents; review it first." >&2
   fi
   printf '%s\n' "===== ${review_tool}: per-file diffs ====="
   diff_rc=0
   git -c "diff.external=${git_review_self}" diff "$@" || diff_rc="$?"
   if [ -s "${git_review_status_file}" ]; then
      printf '%s\n' "${review_tool}: ERROR: undecodable/non-UTF-8 Unicode found during this review (GIT_REVIEW_UNICODE_NONFATAL was set); failing." >&2
      exit 1
   fi
   exit "${diff_rc}"
fi

## External diff driver mode: git passes the 7 args per changed file.
[[ -v git_external_level ]] || git_external_level=0
git_external_level=$((git_external_level + 1))
export git_external_level
if [ "${git_external_level}" -ge 3 ]; then
   printf '%s\n' "${review_tool}: ERROR: external-diff recursion depth '${git_external_level}' reached (>= 3); aborting to avoid a diff loop. This should not happen; please report it." >&2
   exit 255
fi

## Unmerged path: git passes only the path. Do NOT self-diff (that renders
## empty and hides the conflict); show git's combined diff, stcat-neutralized.
if [ "$#" -lt 7 ]; then
   if [ "$#" -eq 0 ]; then
      printf '%s\n' "${review_tool}: ERROR: external diff invoked without a path." >&2
      exit 2
   fi
   unmerged_path_q="$(printf '%q' "${1}")"
   printf '%s\n' "${review_tool}: NOTE: '${unmerged_path_q}' is unmerged (conflict); combined diff:" >&2
   git diff --no-ext-diff --cc -- "${1}" | stcat >&2 || true
   exit 0
fi

diff_path="${1}"
old_file="${2}"
old_hex="${3}"
old_mode="${4}"
new_file="${5}"
new_hex="${6}"
new_mode="${7}"
diff_path_q="$(printf '%q' "${diff_path}")"  ## neutralized for messages

is_submodule_blob() {
   grep --quiet -- '^Subproject commit' "${1}"
}

extract_commit() {
   sed --quiet -- 's/^Subproject commit \([0-9a-fA-F]*\).*/\1/p' "${1}"
}

for check_mode in "${old_mode}" "${new_mode}"; do
   [[ "${check_mode}" =~ ^[0-7]{6}$ ]] \
      || printf '%s\n' "${review_tool}: WARNING: unexpected mode '${check_mode}' for '${diff_path_q}'." >&2
done

## Control bytes in the path (cf. CVE-2025-48384, a trailing CR in a gitlink
## path). Warn on any non-zero: 1 == suspicious, 2 == non-UTF-8 path bytes
## (fatal, cf. git_review_fatal).
path_rc=0
path_report="$(printf '%s\n' "${diff_path}" | UNICODE_SHOW_ALLOW_MISSING_FINAL_NEWLINE=1 NO_COLOR=1 unicode-show 2>&1)" || path_rc="$?"
if [ "${path_rc}" != 0 ]; then
   printf '%s\n' "${review_tool}: WARNING: path '${diff_path_q}' has suspicious/undecodable bytes (unicode-show rc='${path_rc}'):" >&2
   printf '%s\n' "${path_report}" | stcat >&2 || true
   if [ "${path_rc}" -ge 2 ]; then
      git_review_fatal=1
   fi
fi

## Tab / newline are the ONE gap the scan above cannot cover: unicode-show (like
## stcat and grep-find-unicode-wrapper) treats '\t' and '\n' as benign content
## whitespace, so they are never flagged -- yet in a PATH they are anomalous and
## can forge or hide diff-output lines. Everything else (non-ASCII, bidi, CR,
## NUL, non-UTF-8) is delegated to unicode-show above; this only adds the two
## bytes it deliberately allows.
case "${diff_path}" in
   *$'\t'* | *$'\n'*)
      printf '%s\n' "${review_tool}: WARNING: path '${diff_path_q}' contains a tab or newline byte -- anomalous in a filename; it can forge or hide diff-output lines." >&2
      ;;
esac

## Mode/type change (a content diff alone would not show a mode-only change).
if [ "${old_mode}" != "${new_mode}" ]; then
   printf '%s\n' "${review_tool}: MODE CHANGE '${diff_path_q}': '${old_mode}' -> '${new_mode}'"
   case "${new_mode}" in
      100755)
         [ "${old_mode}" = 100755 ] \
            || printf '%s\n' "${review_tool}: NOTE: '${diff_path_q}' is now EXECUTABLE (+x)."
         ;;
   esac
fi

## Symlink: the blob content is the link target. Only the side that IS a symlink
## has one; show it via stcat (a target can carry terminal escapes) and scan it
## for suspicious Unicode. Exit only for a pure symlink change -- a type change
## (file<->symlink) falls through so the regular side is still diffed.
read_target() {
   if [ "${1}" = /dev/null ] || [ ! -e "${1}" ]; then
      printf '(none)'
   elif [ ! -s "${1}" ]; then
      printf '(empty)'
   else
      tr '\n' ' ' < "${1}"
   fi
}

old_is_link=no
if [ "${old_mode:0:2}" = "12" ]; then
   old_is_link=yes
fi
new_is_link=no
if [ "${new_mode:0:2}" = "12" ]; then
   new_is_link=yes
fi
if [ "${old_is_link}" = yes ] || [ "${new_is_link}" = yes ]; then
   ## Label each non-link side accurately: '(none)' when it is absent (a pure
   ## symlink add/delete hands /dev/null), else '(regular file)' (a type change).
   old_target='(regular file)'
   if [ "${old_file}" = /dev/null ]; then
      old_target='(none)'
   fi
   new_target='(regular file)'
   if [ "${new_file}" = /dev/null ]; then
      new_target='(none)'
   fi
   if [ "${old_is_link}" = yes ]; then
      old_target="$(read_target "${old_file}")"
   fi
   if [ "${new_is_link}" = yes ]; then
      new_target="$(read_target "${new_file}")"
   fi
   printf "%s: SYMLINK '%s': '%s' -> '%s'\n" "${review_tool}" "${diff_path}" "${old_target}" "${new_target}" \
      | stcat >&2 || true
   if [ "${old_is_link}" = yes ]; then
      git_review_unicode_scan "${old_file}" "${diff_path_q} old symlink target"
   fi
   if [ "${new_is_link}" = yes ]; then
      git_review_unicode_scan "${new_file}" "${diff_path_q} new symlink target"
   fi
   if [ "${old_is_link}" = yes ] && [ "${new_is_link}" = yes ]; then
      git_review_finish
   fi
fi

## Submodule gitlink -- by MODE (160000), not content (content spoof otherwise).
if [ "${old_mode:0:2}" = "16" ] || [ "${new_mode:0:2}" = "16" ]; then
   old_commit="$(extract_commit "${old_file}")"
   new_commit="$(extract_commit "${new_file}")"
   printf '%s\n' "Submodule '${diff_path_q}': '${old_commit:-<none>}' -> '${new_commit:-<none>}'"
   ## Added or removed submodule (one side has no commit): the transition above
   ## already surfaces it; there is no inner diff to show, and no fetch is
   ## missing -- so do not print a misleading error.
   if [ -z "${old_commit}" ] || [ -z "${new_commit}" ]; then
      printf '%s\n' "${review_tool}: NOTE: submodule '${diff_path_q}' added or removed; no inner diff." >&2
      git_review_finish
   fi
   ## 'git -C' not 'cd' (an odd/symlinked path cannot redirect us); fail loud.
   if ! git -C "${diff_path}" rev-parse --git-dir >/dev/null 2>&1; then
      printf '%s\n' "${review_tool}: ERROR: submodule '${diff_path_q}' not an initialized git repo here; cannot show diff (init/fetch it). NOT hidden." >&2
      exit 1
   fi
   sm_rc=0
   git -C "${diff_path}" diff --no-ext-diff --find-copies --stat "${old_commit}" "${new_commit}" || sm_rc=$?
   git -C "${diff_path}" diff --no-ext-diff --find-copies "${old_commit}" "${new_commit}" || sm_rc=$?
   if [ "${sm_rc}" != 0 ]; then
      printf '%s\n' "${review_tool}: ERROR: submodule '${diff_path_q}' '${old_commit}' -> '${new_commit}': diff unavailable (fetch it). NOT hidden." >&2
      exit 1
   fi
   git_review_finish
fi
if is_submodule_blob "${old_file}" || is_submodule_blob "${new_file}"; then
   printf '%s\n' "${review_tool}: WARNING: '${diff_path_q}' content mimics a gitlink but mode ('${old_mode}' -> '${new_mode}') is not 160000; treating as a regular file (possible obfuscation)." >&2
fi

## Scan the resulting content; for a deletion git hands new_file=/dev/null, so
## fall back to the old side -- otherwise a removed file's Trojan-Source /
## undecodable content is never surfaced (cf. the binary check below).
unicode_scan_file="${new_file}"
if [ "${new_file}" = /dev/null ]; then
   unicode_scan_file="${old_file}"
fi
git_review_unicode_scan "${unicode_scan_file}" "${diff_path_q}"

## Over-long lines can truncate/hang a viewer (a place to bury a change). Check
## BOTH sides: on a deletion new_file=/dev/null, yet the old side is still opened.
longest=0
for longline_blob in "${old_file}" "${new_file}"; do
   [ "${longline_blob}" != /dev/null ] || continue
   blob_longest="$(wc --max-line-length < "${longline_blob}" 2>/dev/null || printf '0')"
   if [ "${blob_longest}" -gt "${longest}" ]; then
      longest="${blob_longest}"
   fi
done
if [ "${longest}" -gt 5000 ]; then
   printf '%s\n' "${review_tool}: WARNING: '${diff_path_q}' has a '${longest}'-char line; a viewer may truncate/hang." >&2
fi

## Check BOTH sides: a deleted binary has new_file=/dev/null, so scanning only
## new_file would miss it and open the old binary in the viewer. '--text' is
## required: without it GNU grep's binary-file heuristic short-circuits and a
## NUL is NOT matched, so a binary blob would be misclassified as text and opened.
is_binary=no
for binary_blob in "${old_file}" "${new_file}"; do
   [ "${binary_blob}" != /dev/null ] || continue
   nul_rc=0
   LC_ALL=C grep --quiet --text --perl-regexp '\x00' -- "${binary_blob}" 2>/dev/null || nul_rc=$?
   if [ "${nul_rc}" = 0 ]; then
      is_binary=yes
   elif [ "${nul_rc}" -ge 2 ]; then
      ## grep itself errored (e.g. no PCRE support) -- fail CLOSED: treat as
      ## binary so a possibly-binary blob is never opened as text.
      is_binary=yes
      printf '%s\n' "${review_tool}: WARNING: NUL check for '${diff_path_q}' errored (grep rc='${nul_rc}'); treating as binary (fail closed)." >&2
   fi
done

## --stat always surfaces the change; the viewer opens only for text (a binary
## blob would render as noise, and the --stat already shows it changed).
git diff --no-ext-diff --find-copies --stat "${old_hex}" "${new_hex}" \
   || printf '%s\n' "${review_tool}: WARNING: '--stat' for '${diff_path_q}' failed; showing the diff anyway." >&2

## Fail closed BEFORE opening a viewer: a fatal (undecodable / non-UTF-8) blob
## must never reach meld/kdiff3, exactly as the difftool/mergetool wrappers gate
## before opening. NONFATAL deferral mode instead falls through to show it
## (stcat-neutralized in the textual driver) and fails at the very end.
if [ "${git_review_fatal}" != 0 ] && [ -z "${GIT_REVIEW_UNICODE_NONFATAL:-}" ]; then
   git_review_finish
fi

if [ "${is_binary}" = yes ]; then
   printf '%s\n' "${review_tool}: NOTE: '${diff_path_q}' looks BINARY (NUL byte); shown as --stat only, not opened in the viewer." >&2
else
   display_regular_file "${old_file}" "${new_file}" "${diff_path_q}"
fi

git_review_finish
