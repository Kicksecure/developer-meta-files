#!/bin/bash

## Copyright (C) 2026 - 2026 ENCRYPTED SUPPORT LLC <adrelanos@whonix.org>
## See the file COPYING for copying conditions.

## AI-Assisted

## Shared content-hardening library for the safe git review tools. Sourced by
## git-review-driver.sh (external-diff mode) AND by the difftool/mergetool
## wrappers (git-review-difftool, git-review-mergetool). Holds the primitives
## that MUST stay identical across every review contract: Unicode/Trojan-Source
## surfacing, the fail-closed fatal handler, and a single-file content scan
## (Unicode + over-long line + binary) shared by the wrappers.
##
## The caller MUST set 'review_tool' (name used in messages) before sourcing.
##
## style-ok: no-strict (sourced-only; the caller sets strict-mode / errexit).

# shellcheck source=../../../../helper-scripts/usr/libexec/helper-scripts/wc-test.sh
source "${HELPER_SCRIPTS_PATH:-}"/usr/libexec/helper-scripts/wc-test.sh
# shellcheck source=../../../../helper-scripts/usr/libexec/helper-scripts/has.sh
source "${HELPER_SCRIPTS_PATH:-}"/usr/libexec/helper-scripts/has.sh
# shellcheck source=../../../../helper-scripts/usr/libexec/helper-scripts/log_run_die.sh
source "${HELPER_SCRIPTS_PATH:-}"/usr/libexec/helper-scripts/log_run_die.sh

has unicode-show
has stcat
has mktemp
has safe-rm

if [ -z "${review_tool:-}" ]; then
  die 2 "git-review-scan.sh: caller must set 'review_tool'"
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
    log warn "'${label}' suspicious/undecodable Unicode (unicode-show rc='${git_review_unicode_rc}'):"
    printf '%s\n' "${report}" | stcat >&2 || true
    if [ "${git_review_unicode_rc}" -ge 2 ]; then
      git_review_handle_unicode_show_fatal
    fi
  fi
}

## Interactively ask the operator whether to continue a review despite content a
## scan flagged. ONLY the terminal-safe reviewer (git-diff-review, which sets
## git_review_display_fatal_content=true and neutralizes ALL output through
## stcat) may prompt; a GUI wrapper never asks. The question goes to stderr via
## 'log question' and the answer is read from /dev/tty, because in external-diff
## mode stdin may be redirected. Consent is cached so a file that trips the scan
## more than once (path plus content) is not re-prompted.
##
## Returns: 0 = proceed (operator said yes, or already consented); 1 = operator
## explicitly declined; 2 = could not ask (not the terminal-safe reviewer, or no
## usable controlling terminal). Callers distinguish 1 from 2: the fatal-blob
## gate fails closed on EITHER, whereas the benign stcat-write path aborts only
## on a real decline (1) and proceeds when nobody could be asked (2).
git_review_continue_consented='false'
git_review_prompt_continue() {
  local reply

  if [ "${git_review_continue_consented}" = 'true' ]; then
    return 0
  fi
  if [ "${git_review_display_fatal_content:-}" != 'true' ]; then
    return 2
  fi
  ## /dev/tty can be a permission-readable device node yet fail to OPEN when the
  ## process has no controlling terminal (ENXIO), so probe by actually opening it
  ## rather than trusting 'test -r'. No usable tty -> cannot ask (rc 2).
  if ! { true < /dev/tty; } 2>/dev/null; then
    return 2
  fi
  log question "the flagged content above was neutralized (stcat). Continue the review anyway? [y/N]"
  reply=''
  read -r reply < /dev/tty 2>/dev/null || return 2
  if [ "${reply,,}" = 'y' ] || [ "${reply,,}" = 'yes' ]; then
    git_review_continue_consented='true'
    return 0
  fi
  return 1
}

git_review_handle_unicode_show_fatal() {
  ## unicode-show reported a fatal (undecodable / non-UTF-8) finding. Files that
  ## trip this are liable to exploit bugs in diff viewers, so the default is to
  ## fail closed. There are two opt-outs, BOTH restricted to the terminal-safe
  ## reviewer (git-diff-review, git_review_display_fatal_content=true, all output
  ## stcat-neutralized) -- a GUI wrapper (git-meld / git-kdiff3) always fails
  ## closed here:
  ##
  ##   1. Scripted: GIT_REVIEW_UNICODE_NONFATAL=1 records the finding in the
  ##      shared flag file and lets the batch run finish, failing at the very end
  ##      (git-review-driver.sh checks the flag file). Needs the flag file, which
  ##      exists only when a wrapper was run directly (see git-review-driver.sh).
  ##   2. Interactive: git_review_prompt_continue asks the operator on /dev/tty;
  ##      a "yes" continues this file CLEANLY (nothing recorded), a "no" or a
  ##      non-interactive run fails closed.
  ##
  ## A non-fatal (rc 1, decodable) finding never reaches here -- it is only
  ## warned about. git_review_unicode_rc may also be >=2 for reasons other than
  ## a decode error (e.g. an unreadable file), so even an opt-out may still fail.

  if [ -n "${GIT_REVIEW_UNICODE_NONFATAL:-}" ] \
    && [ -n "${git_review_fatal_flag_file:-}" ] \
    && [ "${git_review_display_fatal_content:-}" = 'true' ]; then
    ## Record the finding for the end-of-run failure. A write error must NOT be
    ## swallowed - dropping it would let a fatal finding pass as clean.
    if ! printf '%s' '.' > "${git_review_fatal_flag_file}"; then
      ## Explicit 'exit' (NOT 'die', which returns under allow_errors=1) so an
      ## unrecordable fatal finding always fails closed.
      log error "'${diff_path_q:-(file)}' triggered a fatal error in unicode-show and its finding could not be recorded. Failing closed."
      exit 1
    fi
    return 0
  fi

  if git_review_prompt_continue; then
    return 0
  fi

  log error "'${diff_path_q:-(file)}' triggered a fatal error in unicode-show. Failing closed."
  log notice "Hint: To review this diff despite the errors, run via the git-diff-review wrapper and answer the continue prompt, or set GIT_REVIEW_UNICODE_NONFATAL=1. GUI wrappers (git-meld, git-kdiff3) cannot review this diff."
  exit 1
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

  ## Over-long lines can truncate/hang a viewer (a place to bury a change). A wc
  ## failure (e.g. an unreadable target) must not abort the scan under errexit
  ## with a cryptic '[: integer expression expected', nor be read as a huge
  ## line: default to 0.
  longest=0
  longest="$(wc --max-line-length < "${target}")" || longest=0
  if [ "${longest}" -gt 5000 ]; then
    log warn "'${label}' has a '${longest}'-char line; a viewer may truncate/hang."
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
      log warn "NUL check for '${label}' errored (grep rc='${nul_rc}'); treating as binary."
    fi
  fi
}
