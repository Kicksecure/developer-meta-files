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

  ## Detect changes to .gitattributes files. These can be used to manipulate
  ## diff behavior, potentially masking malicious changes, so they must be
  ## flagged and warned about.
  ##
  ## Capture the name list FIRST: piping git straight into grep would, under
  ## pipefail, let a git failure mask a real match and drop this warning.
  ##
  ## FIXME: Shouldn't we error out entirely if git fails here?
  changed_names="$(git diff --no-ext-diff --name-only "$@" 2>/dev/null || true)"
  if printf '%s\n' "${changed_names}" | grep --quiet -e '\(/\|^\)\.gitattributes$'; then
    log warn "'.gitattributes' changed -- can hide OTHER files' contents; review it first."
  fi

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
  ## warn here and exit non-zero.
  if [ -s "${git_review_fatal_flag_file}" ]; then
    die 1 "undecodable/non-UTF-8 Unicode found during this review (GIT_REVIEW_UNICODE_NONFATAL was set); failing."
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
   die 255 "external-diff recursion depth '${git_external_level}' reached (more than 2); aborting to avoid a diff loop. Please report this bug!"
fi

if [ "$#" -eq 0 ]; then
  die 2 "external diff invoked without arguments."
fi

## Unmerged path: git passes a single argument, the path. Show git's combined
## diff, stcat-neutralized.
##
## FIXME: Shouldn't we be scanning this path's filename and contents for
## Unicode and warning about it? stcat neutralizes Unicode but doesn't warn
## about it.
if [ "$#" -lt 7 ]; then
   unmerged_path_q="$(printf '%q' "${1}")"
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
  grep --quiet -E -- '^Subproject commit [0-9a-f]{40}$' "${1}" \
    && [ "$(wc -l < "${1}")" -eq 1 ]
}

extract_commit() {
  sed --quiet -- 's/^Subproject commit \([0-9a-f]\{40\}\).*/\1/p' "${1}"
}

for check_mode in "${old_mode}" "${new_mode}"; do
  [[ "${check_mode}" =~ ^[0-7]{6}$ ]] \
    || log warn "unexpected mode '${check_mode}' for '${diff_path_q}'."
done

## Control bytes in the path (cf. CVE-2025-48384, a trailing CR in a gitlink
## path). Warn on any non-zero: 1 == suspicious, 2 == non-UTF-8 path bytes
## (fatal, handled by git_review_handle_unicode_show_fatal).
##
## No need for UNICODE_SHOW_ALLOW_MISSING_FINAL_NEWLINE=1 here, we append a
## newline to the filename before piping it in.
path_rc=0
path_report="$(printf '%s\n' "${diff_path}" | NO_COLOR=1 unicode-show 2>&1)" || path_rc="$?"
if [ "${path_rc}" != 0 ]; then
  log warn "path '${diff_path_q}' has suspicious/undecodable bytes (unicode-show rc='${path_rc}'):"
  printf '%s\n' "${path_report}" | stcat >&2 || true
  if [ "${path_rc}" -ge 2 ]; then
    git_review_handle_unicode_show_fatal
  fi
fi

## Tab / newline are the ONE gap the scan above cannot cover: unicode-show (like
## stcat and grep-find-unicode-wrapper) treats '\t' and '\n' as benign content
## whitespace, so they are never flagged -- yet in a PATH they are anomalous and
## can forge diff-output lines.
case "${diff_path}" in
  *$'\t'* | *$'\n'*)
    log warn "path '${diff_path_q}' contains a tab or newline byte - anomalous in a filename; it can forge diff-output lines."
    ;;
esac

## Mode/type change (a content diff alone would not show a mode-only change).
if [ "${old_mode}" != "${new_mode}" ]; then
  printf '%s\n' "${review_tool}: MODE CHANGE '${diff_path_q}': '${old_mode}' -> '${new_mode}'"
  if [[ "${new_mode:3:3}" =~ [1357] ]] && ! [[ "${old_mode:3:3}" =~ [1357] ]]; then
    printf '%s\n' "${review_tool}: NOTE: '${diff_path_q}' is now EXECUTABLE (+x)."
  fi
fi

## Symlink detection and handling.
read_target() {
  if [ "${1}" = /dev/null ] || [ ! -e "${1}" ]; then
    printf '(none)'
  elif [ ! -s "${1}" ]; then
    printf '(empty)'
  else
    if [ "$(git config get core.symlinks)" = 'true' ]; then
      tr '\n' ' ' < <(readlink --no-newline "${1}")
    else
      tr '\n' ' ' < "${1}"
    fi
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
    ## TODO: It's not possible for old_file to be /dev/null and be a symlink,
    ## is it?
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

  ## FIXME: This logic does different things depending on what 'core.symlinks'
  ## is set to in Git. If it is set to 'true', this will scan the files the
  ## symlinks point to. If it is set to 'false', this will scan the symlink
  ## paths. We probably only want to do one or the other, and should adjust
  ## this accordingly.
  if [ "${old_is_link}" = 'true' ]; then
    git_review_unicode_scan "${old_file}" "'${diff_path_q}' old symlink target"
  fi
  if [ "${new_is_link}" = 'true' ]; then
    git_review_unicode_scan "${new_file}" "'${diff_path_q}' new symlink target"
  fi

  ## If either side is not a symlink, contine so that we diff the non-symlink
  ## and the contents of the file the symlink points to.
  ##
  ## TODO: Shouldn't we continue past here even if both files are symlinks? If
  ## a symlink changed target, it might be useful to see the difference
  ## between the old target and the new target.
  if [ "${old_is_link}" = 'true' ] && [ "${new_is_link}" = 'true' ]; then
    exit 0
  fi
fi

## Submodule gitlink -- by MODE, not content (content spoof otherwise).
## Git uses the 160000 file mode to signal that gitlinks are being used, see
## https://github.com/git/git/blob/f85a7e662054a7b0d9070e432508831afa214b47/object.h#L118
## TODO: Match against the full 160000 mode rather than just the first two
## digits?
if [ "${old_mode:0:2}" = "16" ] || [ "${new_mode:0:2}" = "16" ]; then
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

  ## The submodule's own diff is untrusted content (a malicious commit's file
  ## bytes) shown on the terminal, so neutralize it through stcat like every
  ## other untrusted line here -- otherwise it is a terminal-escape injection
  ## vector for the textual reviewer. pipefail makes a git failure (bad object)
  ## still set sm_rc.
  ##
  ## TODO: Don't we want to recursively execute the review tool wrapper in the
  ## submodules? Dumping the diff output to the terminal is only marginally
  ## better than what we had without this tool.
  sm_rc=0
  git -C "${diff_path}" diff --no-ext-diff --find-copies --stat "${old_commit}" "${new_commit}" | stcat || sm_rc=$?
  git -C "${diff_path}" diff --no-ext-diff --find-copies "${old_commit}" "${new_commit}" | stcat || sm_rc=$?
  if [ "${sm_rc}" != 0 ]; then
    log error "submodule '${diff_path_q}' '${old_commit}' to '${new_commit}': diff failed with exit code '${sm_rc}'. Failing closed."
    log notice "Hint: One or more commits being diffed may be missing. Try running 'git fetch' in the submodule."
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

## Display a brief overview of changes. This is mostly useful to flag changes
## in binaries. Pipe output through stcat to avoid rendering escape codes in
## filenames.
##
## FIXME: Shouldn't we error out entirely if `git diff` fails here? There's no
## good reason this command should fail.
##
## FIXME: Should we add "${diff_path}" as a third argument? If we don't, we'll
## end up displaying a lot more changes than just changes for the current
## file.
git diff --no-ext-diff --find-copies --stat "${old_hex}" "${new_hex}" | stcat \
  || log warn "'--stat' for '${diff_path_q}' failed; showing the diff anyway."

if [ "${is_binary}" = 'true' ]; then
  log notice "'${diff_path_q}' looks BINARY (NUL byte); shown as --stat only, not opened in the viewer."
else
  display_regular_file "${old_file}" "${new_file}" "${diff_path_q}"
fi

exit 0
