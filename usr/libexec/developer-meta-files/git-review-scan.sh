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

# shellcheck source=../../../../helper-scripts/usr/libexec/helper-scripts/has.sh
source "${HELPER_SCRIPTS_PATH:-}"/usr/libexec/helper-scripts/has.sh

has unicode-show
has stcat
has mktemp
has safe-rm

[ -n "${review_tool:-}" ] \
   || { printf '%s\n' "git-review-scan.sh: caller must set 'review_tool'" >&2; exit 2; }

## Fatal-finding flag: set to 1 once an undecodable/non-UTF-8 (unicode-show
## rc 2) blob or path is seen this run. A decodable non-ASCII finding (rc 1) is
## warned but is NOT fatal. Consumed by git_review_finish.
git_review_fatal=0

## Env var suppresses unicode-show's benign "missing newline at end" finding.
## Warn on ANY non-zero exit: 1 == suspicious found, 2 == undecodable/non-UTF-8
## (fail-closed -- treat as fatal, never silently pass). git_review_unicode_rc
## is intentionally a global (not a local): callers read the last scan's exit.
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
         git_review_fatal=1
      fi
   fi
}

## Every non-error exit routes through this so a fatal Unicode finding is never
## rendered as a clean review: by default it exits non-zero (git then aborts the
## diff). Set GIT_REVIEW_UNICODE_NONFATAL to a non-empty value to let the review
## run to completion instead; the finding is recorded to the shared status file
## and the re-dispatch block still exits non-zero at the very end.
git_review_finish() {
   if [ "${git_review_fatal}" != 0 ]; then
      ## Deferral is only possible when BOTH the operator opted in AND a status
      ## file exists to defer to. Without the status file (e.g. wired directly as
      ## git's 'diff.external', bypassing the re-dispatch block that creates it)
      ## there is nowhere to record the finding, so fail closed NOW rather than
      ## fall through to 'exit 0' and let git see a clean external diff.
      if [ -n "${GIT_REVIEW_UNICODE_NONFATAL:-}" ] && [ -n "${git_review_status_file:-}" ]; then
         ## Record the finding for the end-of-run failure. A write error must NOT
         ## be swallowed -- dropping it would let a fatal finding pass as clean.
         if ! printf '%s\n' "fatal-unicode '${diff_path_q:-(file)}'" >> "${git_review_status_file}"; then
            printf '%s\n' "${review_tool}: ERROR: '${diff_path_q:-(file)}' has undecodable/non-UTF-8 Unicode and its finding could not be recorded; failing." >&2
            exit 1
         fi
      else
         printf '%s\n' "${review_tool}: ERROR: '${diff_path_q:-(file)}' contains undecodable/non-UTF-8 Unicode; failing the review (to continue and fail only at the end, set GIT_REVIEW_UNICODE_NONFATAL=1 AND run via the git-meld/git-kdiff3/git-diff-review wrapper, which provides the status file)." >&2
         exit 1
      fi
   fi
   exit 0
}

## Trap target (invoked indirectly via 'trap ... EXIT', not dead code): remove
## the shared status file created by the re-dispatch block.
# shellcheck disable=SC2317
git_review_cleanup() {
   if [ -n "${git_review_status_file:-}" ]; then
      safe-rm --force -- "${git_review_status_file}"
   fi
}

## Content-hardening scan for a single file, contract-independent (it operates
## on file CONTENTS only). Shared by the difftool/mergetool wrappers, which --
## unlike the external-diff driver -- receive two/four already-materialized file
## paths and no git mode/hex metadata, so the driver's side-aware inline scan
## (mode-only / symlink / gitlink, /dev/null add-delete semantics) does not
## apply. Surfaces Trojan-Source Unicode and over-long lines; sets
## git_review_is_binary=yes|no so the caller can refuse to open a binary blob in
## a GUI. Does NOT exit; the caller calls git_review_finish to fail closed.
git_review_is_binary=no
git_review_scan_content() {
   local target label longest nul_rc

   target="$1"
   label="$2"

   git_review_unicode_scan "${target}" "${label}"

   ## Over-long lines can truncate/hang a viewer (a place to bury a change).
   longest="$(awk '{ if (length > m) m = length } END { print m + 0 }' "${target}" 2>/dev/null || printf '0')"
   if [ "${longest}" -gt 5000 ]; then
      printf '%s\n' "${review_tool}: WARNING: '${label}' has a '${longest}'-char line; a viewer may truncate/hang." >&2
   fi

   ## A binary blob would render as noise in a text/GUI viewer. '--text' is
   ## required: without it GNU grep's binary-file heuristic short-circuits and a
   ## NUL is NOT matched, so the blob would be misclassified as text and opened.
   ## grep rc: 0 == NUL found, 1 == none, >=2 == grep error -> fail CLOSED (treat
   ## as binary) so a possibly-binary blob is never opened as text.
   git_review_is_binary=no
   if [ "${target}" != /dev/null ]; then
      nul_rc=0
      LC_ALL=C grep --quiet --text --perl-regexp '\x00' -- "${target}" 2>/dev/null || nul_rc=$?
      if [ "${nul_rc}" = 0 ]; then
         git_review_is_binary=yes
      elif [ "${nul_rc}" -ge 2 ]; then
         git_review_is_binary=yes
         printf '%s\n' "${review_tool}: WARNING: NUL check for '${label}' errored (grep rc='${nul_rc}'); treating as binary (fail closed)." >&2
      fi
   fi
}
