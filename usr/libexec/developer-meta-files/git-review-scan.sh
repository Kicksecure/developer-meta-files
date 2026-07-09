#!/bin/bash

## Copyright (C) 2026 - 2026 ENCRYPTED SUPPORT LLC <adrelanos@whonix.org>
## See the file COPYING for copying conditions.

## AI-Assisted

## Shared content-hardening library for the safe git review tools. Sourced by
## git-review-driver.sh (external-diff mode) AND by the difftool/mergetool
## wrappers (git-review-difftool, git-review-mergetool). Holds the primitives
## that MUST stay identical across every review contract: Unicode/Trojan-Source
## surfacing, the fatal-finding flag, the fail-closed finish, and a single-file
## content scan (Unicode + over-long line + binary) shared by the wrappers.
##
## The caller MUST set 'review_tool' (name used in messages) before sourcing.
## git_review_finish reads 'diff_path_q' (defaulted here when a caller -- e.g.
## the difftool wrapper -- has not set a per-file path).
##
## style-ok: no-strict (sourced-only; the caller sets strict-mode / errexit).

# shellcheck source=../../../../helper-scripts/usr/libexec/helper-scripts/wc-test.sh
source "${HELPER_SCRIPTS_PATH:-}"/usr/libexec/helper-scripts/wc-test.sh
# shellcheck source=../../../../helper-scripts/usr/libexec/helper-scripts/has.sh
source "${HELPER_SCRIPTS_PATH:-}"/usr/libexec/helper-scripts/has.sh

has unicode-show
has stcat
has mktemp
has safe-rm

if [ -z "${review_tool:-}" ]; then
  printf '%s\n' "git-review-scan.sh: caller must set 'review_tool'" >&2
  exit 2
fi

## Check for Unicode in a specified file. Makes unicode-show's return value
## public for other functions to inspect. Warns if Unicode is found, errors
## out or sets the fatal-finding flag if unicode-show reports a critical error
## or non-UTF data.
##
## unicode-show exits 0 on success when no Unicode is found, 1 on success when
## Unicode is found, 2 on errors including text decode errors. We
## intentionally suppress "missing newline at end" findings because symlink
## target placeholders in Git lack a trailing newline by design.
git_review_unicode_rc=0
git_review_unicode_scan() {
  local target label report

  target="$1"
  label="$2"
  git_review_unicode_rc=0
  report="$(UNICODE_SHOW_ALLOW_MISSING_FINAL_NEWLINE=1 NO_COLOR=1 unicode-show "${target}" 2>&1)" \
    || git_review_unicode_rc="$?"
  if [ "${git_review_unicode_rc}" != 0 ]; then
    printf '%s\n' "${review_tool}: WARNING: '${label}' suspicious/undecodable Unicode (unicode-show rc='${git_review_unicode_rc}'):" >&2
    printf '%s\n' "${report}" | stcat >&2 || true
    if [ "${git_review_unicode_rc}" -ge 2 ]; then
      git_review_handle_unicode_show_fatal
    fi
  fi
}

git_review_handle_unicode_show_fatal() {
  ## Usually we want to simply exit non-zero here. However, the user might
  ## want to try to review a diff even if a UTF-8 decode error was thrown
  ## by unicode-show. Because files that trigger such errors are liable to
  ## exploit vulnerabilities in diff viewers, we only allow this if:
  ##
  ## * the user has set GIT_REVIEW_UNICODE_NONFATAL=1 in the environment,
  ##   AND
  ## * git_review_fatal_flag_file points to a file where we can store info
  ##   about problematic files (this happens only when one of the wrappers
  ##   is called directly, see git-review-driver.sh), AND
  ## * the diff viewer plugin has declared itself able to display possibly
  ##   malicious files safely.
  ##
  ## At time of writing, the only diff viewer plugin that fulfills the
  ## third requirement is git-diff-review, which pipes all output through
  ## stcat.
  ##
  ## Note that git_review_fatal may have been set to non-zero for reasons
  ## reason other than a failed UTF-8 decode attempt (e.g., unreadable
  ## files will trigger this as well), so even if all of these conditions
  ## hold, the diff may still fail.

  if [ -n "${GIT_REVIEW_UNICODE_NONFATAL:-}" ] \
    && [ -n "${git_review_fatal_flag_file:-}" ] \
    && [ "${git_review_display_fatal_content:-}" = 'true' ]; then
    ## Record the finding for the end-of-run failure. A write error must
    ## NOT be swallowed - dropping it would let a fatal finding pass as
    ## clean.
    if ! printf '%s' '.' > "${git_review_fatal_flag_file}"; then
      printf '%s\n' "${review_tool}: ERROR: '${diff_path_q:-(file)}' triggered a fatal error in unicode-show and its finding could not be recorded. Failing closed." >&2
      exit 1
    fi
  else
    printf '%s\n' "${review_tool}: ERROR: '${diff_path_q:-(file)}' triggered a fatal error in unicode-show. Failing closed." >&2
    printf '%s\n' "${review_tool}: Hint: To review this diff despite the errors, set GIT_REVIEW_UNICODE_NONFATAL=1 and run via the git-diff-review wrapper. GUI wrappers (git-meld, git-kdiff3) cannot be used to review this diff." >&2
    exit 1
  fi
}

## Trap target: remove the fatal flag file if it exists.
# shellcheck disable=SC2317
git_review_cleanup() {
  if [ -n "${git_review_fatal_flag_file:-}" ]; then
    safe-rm --force -- "${git_review_fatal_flag_file}"
  fi
}

## Check a specified file for Unicode and overly long lines, and warn if
## either is found. Also checks a file for binary content and sets
## get_review_is_binary to 'true' if detected.
##
## TODO: Right now this is used only by git-review-difftool and
## git-review-mergetool. Equivalent functionality is also implemented for the
## diff plugins in git-review-driver.sh. Can we deduplicate?
git_review_is_binary='false'
git_review_scan_content() {
  local target label longest nul_rc

  target="$1"
  label="$2"

  git_review_unicode_scan "${target}" "${label}"

  ## Over-long lines can truncate/hang a viewer (a place to bury a change).
  ## Do not silence errors from wc, if it fails something is very wrong.
  longest="$(wc --max-line-length < "${target}" 2>/dev/null)"
  if [ "${longest}" -gt 5000 ]; then
    printf '%s\n' "${review_tool}: WARNING: '${label}' has a '${longest}'-char line; a viewer may truncate/hang." >&2
  fi

  ## A binary blob would render as noise in a text/GUI viewer. '--text' is
  ## required: without it GNU grep's binary-file heuristic will report no NUL
  ## matches, causing us to misclassify a file as text.
  ##
  ## grep rc: 0 == NUL found, 1 == none, >= 2 == grep error. We treat grep
  ## errors as binary so a possibly-binary blob is never opened as text.
  ##
  ## Do NOT use the --quiet option of grep, this causes errors to result in an
  ## exit code of 0!
  git_review_is_binary='false'
  if [ "${target}" != /dev/null ]; then
    nul_rc=0
    LC_ALL=C grep --text --perl-regexp '\x00' -- "${target}" >/dev/null 2>&1 || nul_rc=$?
    if [ "${nul_rc}" = 0 ]; then
      git_review_is_binary='true'
    elif [ "${nul_rc}" -ge 2 ]; then
      git_review_is_binary='true'
      printf '%s\n' "${review_tool}: WARNING: NUL check for '${label}' errored (grep rc='${nul_rc}'); treating as binary." >&2
    fi
  fi
}
