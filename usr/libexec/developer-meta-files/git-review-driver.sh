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

# shellcheck source=../../../../helper-scripts/usr/libexec/helper-scripts/wc-test.sh
source "${HELPER_SCRIPTS_PATH:-}"/usr/libexec/helper-scripts/wc-test.sh
# shellcheck source=../../../../helper-scripts/usr/libexec/helper-scripts/log_run_die.sh
source "${HELPER_SCRIPTS_PATH:-}"/usr/libexec/helper-scripts/log_run_die.sh

## The path to the executable tool that uses this wrapper.
if [ -z "${git_review_self:-}" ]; then
  die 2 "git-review-driver.sh: wrapper must set 'git_review_self'"
fi

## The name of the tool.
if [ -z "${review_tool:-}" ]; then
  die 2 "git-review-driver.sh: wrapper must set 'review_tool'"
fi

## The function to call to render a diff and display it to the user.
if ! declare -F display_regular_file >/dev/null 2>&1; then
  die 2 "git-review-driver.sh: wrapper must define 'display_regular_file()'"
fi

## Shared content-hardening core.
# shellcheck source=./git-review-scan.sh
source /usr/libexec/developer-meta-files/git-review-scan.sh

if [ -z "${GIT_DIFF_PATH_TOTAL:-}" ]; then
  ## Wrapper was executed directly. Re-execute the wrapper with `git diff` to
  ## run it on every changed file.

  ## If the user ran a wrapper via a Git alias, it will be executing from
  ## the repository root, whereas we want to be in the user's current working
  ## directory. GIT_PREFIX contains the relative path to that dir, so change
  ## to it. If the user ran the wrapper directly, it will execute in the
  ## current working directory already.
  cd -- "${GIT_PREFIX:-.}" || exit 1

  ## Shared status file: if fatal Unicode errors are detected but are being
  ## tolerated, the scan scripts will make this file non-empty. This indicates
  ## that the script should fail before displaying diff output to the user.
  git_review_fatal_flag_file="$(mktemp --tmpdir git-review-fatal-flag.XXXXXX)"
  export git_review_fatal_flag_file

  trap git_review_cleanup EXIT

  ## Display a diffstat and file change summary to the user first, since this
  ## may display changes that Git won't use a diff driver to display.
  printf '%s\n' "===== ${review_tool}: diffstat and summary of full change set ====="
  git diff --no-ext-diff --stat --summary --find-renames "$@" || true

  ## Fail closed on a .gitattributes change in the reviewed range (it can remap
  ## diff behavior to hide other files' content). The gate helper runs the given
  ## '--name-only -z' command itself and detects robustly (raw names, no
  ## quoting, no fail-open pipe); see git-review-scan.sh.
  git_review_gitattributes_gate "the change set" \
    git diff --no-ext-diff --name-only -z "$@"

  ## Display file diffs one at a time. The terminal-safe reviewer
  ## (git-diff-review) may prompt on /dev/tty to continue past flagged content,
  ## so disable git's pager for it -- a pager would fight the prompt for the
  ## terminal. GUI drivers (git-meld / git-kdiff3) keep the pager.
  printf '%s\n' "===== ${review_tool}: per-file diffs ====="
  git_pager_opt=()
  if [ "${git_review_display_fatal_content:-}" = 'true' ]; then
    git_pager_opt=(--no-pager)
  fi
  diff_rc=0
  git "${git_pager_opt[@]}" -c "diff.external=${git_review_self}" diff "$@" || diff_rc="$?"

  ## If a fatal error was encountered while checking for malicious Unicode,
  ## warn here and exit non-zero. Explicit 'exit' (NOT 'die', which returns
  ## instead of exiting under allow_errors=1) so a recorded fatal finding can
  ## never report success.
  if [ -s "${git_review_fatal_flag_file}" ]; then
    log error "undecodable/non-UTF-8 Unicode found during this review (GIT_REVIEW_UNICODE_NONFATAL was set); failing."
    exit 1
  fi
  exit "${diff_rc}"
fi

## Wrapper was executed by git diff. Parse arguments and do real file comparisons.
##
## Don't allow overly deep recursive execution. Some recursion may be
## expected, but of we ever recurse more than two levels deep, something is
## wrong.
[[ -v git_external_level ]] || git_external_level=0
git_external_level=$((git_external_level + 1))
export git_external_level
if [ "${git_external_level}" -gt 2 ]; then
   ## Explicit 'exit' (NOT 'die', which returns under allow_errors=1) so a diff
   ## loop cannot be resumed past this guard.
   log error "external-diff recursion depth '${git_external_level}' reached (more than 2); aborting to avoid a diff loop. Please report this bug!"
   exit 255
fi

if [ "$#" -eq 0 ]; then
  die 2 "external diff invoked without arguments."
fi

## Unmerged path: git passes a single argument, the path. Warn about a
## suspicious/undecodable or tab/newline conflict FILENAME -- warn only, do not
## fail closed on it: the combined diff below is already stcat-neutralized and
## the operator still needs to see the conflict. Then show it.
if [ "$#" -lt 7 ]; then
   unmerged_path_q="$(printf '%q' "${1}")"
   git_review_scan_path "${1}" "${unmerged_path_q}"
   log notice "'${unmerged_path_q}' is unmerged (conflict). Combined diff:"
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
  local bytes blob_rc
  ## A gitlink blob is exactly 'Subproject commit ' (18 bytes) + 40 hex = 58
  ## bytes, plus an optional trailing newline (59). Bound on the byte size, not a
  ## line count: 'wc -l' counts newlines, so a one-line blob with NO trailing
  ## newline yields 0 and the spoof warning is trivially evaded. The size bound
  ## also rejects (and avoids slurping) any larger file.
  bytes="$(wc -c < "${1}")"
  if [ "${bytes}" != 58 ] && [ "${bytes}" != 59 ]; then
    return 1
  fi
  ## grep WITHOUT --quiet drains the (tiny) file, so a read error surfaces as
  ## rc >= 2 instead of being masked by an early-match exit 0.
  blob_rc=0
  grep -E -- '^Subproject commit [0-9a-f]{40}$' "${1}" >/dev/null || blob_rc=$?
  [ "${blob_rc}" = 0 ]
}

extract_commit() {
  sed --quiet -- 's/^Subproject commit \([0-9a-f]\{40\}\).*/\1/p' "${1}"
}

for check_mode in "${old_mode}" "${new_mode}"; do
  [[ "${check_mode}" =~ ^[0-7]{6}$ ]] \
    || log warn "unexpected mode '${check_mode}' for '${diff_path_q}'."
done

## Control bytes in the path (cf. CVE-2025-48384, a trailing CR in a gitlink
## path). git_review_scan_path warns on suspicious (rc 1) / undecodable (rc 2)
## bytes and on tab/newline forgery; a fatal (rc >= 2) path is failed closed
## here, before any viewer opens.
git_review_scan_path "${diff_path}" "${diff_path_q}"
if [ "${git_review_path_rc}" -ge 2 ]; then
  git_review_handle_unicode_show_fatal
fi

## Mode/type change (a content diff alone would not show a mode-only change).
if [ "${old_mode}" != "${new_mode}" ]; then
  printf '%s\n' "${review_tool}: MODE CHANGE '${diff_path_q}': '${old_mode}' -> '${new_mode}'"
  if [[ "${new_mode:3:3}" =~ [1357] ]] && ! [[ "${old_mode:3:3}" =~ [1357] ]]; then
    printf '%s\n' "${review_tool}: NOTE: '${diff_path_q}' is now EXECUTABLE (+x)."
  fi
fi

## Symlink detection and handling.
read_target() {
  ## Test '-L' FIRST: '-e' and '-s' FOLLOW a symlink to its target, so a real
  ## on-disk symlink (working-tree side, core.symlinks=true) that is dangling or
  ## points at an empty file would otherwise be mislabeled '(none)' / '(empty)',
  ## hiding its target. A real symlink is read with readlink; git's regular temp
  ## blob (external-diff mode: content IS the target path) is read as content --
  ## discriminate by what the file actually IS, NOT by 'git config core.symlinks'
  ## (readlink on the temp blob would fail and render the target empty).
  if [ -L "${1}" ]; then
    tr '\n' ' ' < <(readlink --no-newline -- "${1}")
  elif [ "${1}" = /dev/null ] || [ ! -e "${1}" ]; then
    printf '(none)'
  elif [ ! -s "${1}" ]; then
    printf '(empty)'
  else
    tr '\n' ' ' < "${1}"
  fi
}

## A file type of `12` is a symlink, see inode(7) manpage
old_is_link='false'
if [ "${old_mode:0:2}" = "12" ]; then
   old_is_link='true'
fi
new_is_link='false'
if [ "${new_mode:0:2}" = "12" ]; then
   new_is_link='true'
fi
if [ "${old_is_link}" = 'true' ] || [ "${new_is_link}" = 'true' ]; then
  ## Label each non-link side accurately: '(none)' when it is absent (a pure
  ## symlink add/delete hands /dev/null), else '(regular file)' (a type change).
  if [ "${old_file}" = /dev/null ]; then
    ## /dev/null is the absent side of an add/delete (mode 000000), never a
    ## symlink side (a symlink side has a real blob temp file), so old_is_link is
    ## false here; this only labels the absent side.
    old_target='(none)'
  elif [ "${old_is_link}" = 'true' ]; then
    old_target="$(read_target "${old_file}")"
  else
    old_target='(regular file)'
  fi
  if [ "${new_file}" = /dev/null ]; then
    new_target='(none)'
  elif [ "${new_is_link}" = 'true' ]; then
    new_target="$(read_target "${new_file}")"
  else
    new_target='(regular file)'
  fi
  printf "%s: SYMLINK '%s': '%s' -> '%s'\n" "${review_tool}" "${diff_path}" "${old_target}" "${new_target}" \
    | stcat >&2 || true

  ## Scan each symlink side's target string. In external-diff mode the side is a
  ## regular temp file whose content IS the target path (read_target reads it the
  ## same way, via '[ -L ]'), so this is consistent regardless of git's
  ## core.symlinks setting.
  if [ "${old_is_link}" = 'true' ]; then
    git_review_unicode_scan "${old_file}" "'${diff_path_q}' old symlink target"
  fi
  if [ "${new_is_link}" = 'true' ]; then
    git_review_unicode_scan "${new_file}" "'${diff_path_q}' new symlink target"
  fi

  ## If exactly ONE side is a symlink (a file<->symlink type change), fall
  ## through so the regular side is still diffed. If BOTH sides are symlinks (a
  ## retarget), the SYMLINK line above already shows old -> new; also show a
  ## neutralized unified diff of the two target strings so a change inside a long
  ## target is easy to spot, then this file is done.
  if [ "${old_is_link}" = 'true' ] && [ "${new_is_link}" = 'true' ]; then
    diff --unified -- "${old_file}" "${new_file}" | stcat >&2 || true
    exit 0
  fi
fi

## Submodule gitlink -- by MODE, not content (content spoof otherwise).
## Git uses the 160000 file mode to signal that gitlinks are being used, see
## https://github.com/git/git/blob/f85a7e662054a7b0d9070e432508831afa214b47/object.h#L118
if [ "${old_mode}" = "160000" ] || [ "${new_mode}" = "160000" ]; then
  old_commit="$(extract_commit "${old_file}")"
  new_commit="$(extract_commit "${new_file}")"
  printf '%s\n' "Submodule '${diff_path_q}': '${old_commit:-<none>}' -> '${new_commit:-<none>}'"
  ## Added or removed submodule (one side has no commit): the transition above
  ## already surfaces it; there is no inner diff to show, and no fetch is
  ## missing -- so do not print a misleading error.
  if [ -z "${old_commit}" ] || [ -z "${new_commit}" ]; then
    log notice "submodule '${diff_path_q}' added or removed; no inner diff."
    exit 0
  fi
  ## We can NOT use `git rev-parse --git-dir` to detect initialization; a
  ## fresh checkout of derivative-maker with no submodules initialized had
  ## git dirs for each uninitialized submodule. Use
  ## `git submodule status path/to/module` instead. If a submodule is not
  ## initialized, the output from `git submodule status` will start with a
  ## `-` character.
  if [[ "$(git submodule status "${diff_path}" 2>/dev/null)" =~ ^- ]]; then
    log error "submodule '${diff_path_q}' not an initialized git repo; cannot show diff. Failing closed."
    log notice "Hint: Use 'git submodule update --init --recursive --progress --jobs=4' to initialize all submodules."
    exit 1
  fi

  ## The recursion below reviews the submodule's files in EXTERNAL-DIFF mode,
  ## which bypasses the top-level re-dispatch preflight -- so re-run the
  ## .gitattributes gate here on the submodule's own change, else a submodule
  ## bump that adds a hiding .gitattributes would slip through.
  git_review_gitattributes_gate "submodule '${diff_path_q}'" \
    git -C "${diff_path}" diff --no-ext-diff --name-only -z "${old_commit}" "${new_commit}"

  ## First a neutralized --stat summary of the submodule's own change (untrusted
  ## content, so through stcat), then review each changed submodule file by
  ## running THIS review tool as the submodule's external diff -- so submodule
  ## files get the SAME hardening/neutralization as top-level files, not a raw
  ## dump. This is the single level of recursion the depth guard above permits:
  ## this gitlink is git_external_level 1, the submodule's files are level 2, and
  ## a submodule-of-a-submodule would hit the '> 2' abort. The fatal-flag file is
  ## exported, so undecodable content inside the submodule still fails the whole
  ## review closed; --no-pager avoids a nested pager. The recursive git diff
  ## does NOT need '| stcat' -- the review tool neutralizes each file itself.
  sm_rc=0
  git -C "${diff_path}" --no-pager diff --no-ext-diff --find-copies --stat \
    "${old_commit}" "${new_commit}" | stcat || sm_rc=$?
  git -C "${diff_path}" --no-pager -c "diff.external=${git_review_self}" \
    diff --find-copies "${old_commit}" "${new_commit}" || sm_rc=$?
  if [ "${sm_rc}" != 0 ]; then
    log error "submodule '${diff_path_q}' '${old_commit}' to '${new_commit}': inner review failed (rc '${sm_rc}'). Failing closed."
    log notice "Hint: a missing commit (run 'git fetch' in the submodule) or fatal content inside the submodule."
    exit 1
  fi
  exit 0
fi
if is_submodule_blob "${old_file}" || is_submodule_blob "${new_file}"; then
  log warn "'${diff_path_q}' content mimics a gitlink but mode ('${old_mode}' to '${new_mode}') is not 160000; treating as a regular file. Possible obfuscation?"
fi

## Scan files for Unicode, over-long lines, and binary content. Always check
## both old and new files since either of them could trigger bugs in diff
## viewers.
is_binary='false'
if [ "${old_file}" != '/dev/null' ]; then
  git_review_scan_content "${old_file}" "old version of '${diff_path_q}'"
  is_binary="${git_review_is_binary}"
fi
if [ "${new_file}" != '/dev/null' ]; then
  git_review_scan_content "${new_file}" "new version of '${diff_path_q}'"
  if [ "${is_binary}" != 'true' ]; then
    is_binary="${git_review_is_binary}"
  fi
fi

## Display a brief overview of changes, mainly to flag binaries. Diff the two
## materialized blobs with --no-index (via their file paths, not the blob
## hashes) so it also works for an add or a delete: there git passes the
## all-zero hash for the absent side, and 'git diff <hex> <hex>' rejects that as
## a bad object and drops the overview for exactly those cases (a binary add
## would then be surfaced nowhere here). --no-ext-diff keeps this from
## re-entering the external-diff driver. --no-index exits 1 when the files
## differ (every change that reaches this point) and >1 on a real error, so only
## a >1 rc is a failure. Pipe through stcat to neutralize escape codes in paths;
## read git's own rc from PIPESTATUS so a benign stcat exit is not misread.
stat_rc=0
git diff --no-ext-diff --no-index --stat -- "${old_file}" "${new_file}" | stcat \
  || stat_rc="${PIPESTATUS[0]}"
if [ "${stat_rc}" -gt 1 ]; then
  log warn "'--stat' for '${diff_path_q}' failed; showing the diff anyway."
fi

if [ "${is_binary}" = 'true' ]; then
  log notice "'${diff_path_q}' looks BINARY (NUL byte); shown as --stat only, not opened in the viewer."
else
  display_regular_file "${old_file}" "${new_file}" "${diff_path_q}"
fi

exit 0
