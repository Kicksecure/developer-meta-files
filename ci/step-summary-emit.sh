#!/bin/bash

## Copyright (C) 2026 - 2026 ENCRYPTED SUPPORT LLC <adrelanos@whonix.org>
## See the file COPYING for copying conditions.

## AI-Assisted

## Append a uniform markdown panel to GitHub Actions' step summary
## (${GITHUB_STEP_SUMMARY}). Generic across tools; one panel per
## invocation. No-op when GITHUB_STEP_SUMMARY is unset, so callers
## can use it unconditionally - a local developer run produces no
## output and a GHA run produces a rendered panel.
##
## Helper is intentionally self-contained: no helper-scripts source,
## no R-040 log dependency. Same R-093 carve-out as agents/
## pre-push-static.sh, since this script can be called from any
## workflow context including ones that have not yet installed
## helper-scripts.
##
## Usage:
##   ci/step-summary-emit.sh \
##      --tool          'tool-name (run context)' \
##      [--column-header 'outcome'] \
##      [--row 'passed=27'] \
##      [--row 'failed=0']  \
##      [--total 27] \
##      [--details-url 'https://...'] \
##      [--extra 'Failures:|- foo|- bar']
##
## --row repeats; first column header defaults to 'item'. --extra is
## a single string with '|'-separated lines (shell-flag-friendly
## multi-line escape). Newlines inside cells are not supported.

set -o errexit
set -o nounset
set -o pipefail
set -o errtrace
shopt -s inherit_errexit
shopt -s shift_verbose

tool=''
column_header='item'
total=''
details_url=''
extra=''
declare -a rows=()

while [ "$#" -gt 0 ]; do
   case "$1" in
      --tool)
         [ "$#" -ge 2 ] || { printf '%s\n' 'missing value for --tool' >&2; exit 64; }
         tool="$2"
         shift 2
         ;;
      --column-header)
         [ "$#" -ge 2 ] || { printf '%s\n' 'missing value for --column-header' >&2; exit 64; }
         column_header="$2"
         shift 2
         ;;
      --row)
         [ "$#" -ge 2 ] || { printf '%s\n' 'missing value for --row' >&2; exit 64; }
         rows+=( "$2" )
         shift 2
         ;;
      --total)
         [ "$#" -ge 2 ] || { printf '%s\n' 'missing value for --total' >&2; exit 64; }
         total="$2"
         shift 2
         ;;
      --details-url)
         [ "$#" -ge 2 ] || { printf '%s\n' 'missing value for --details-url' >&2; exit 64; }
         details_url="$2"
         shift 2
         ;;
      --extra)
         [ "$#" -ge 2 ] || { printf '%s\n' 'missing value for --extra' >&2; exit 64; }
         extra="$2"
         shift 2
         ;;
      --)
         shift
         break
         ;;
      -h|--help)
         sed -n -- 's/^## \{0,1\}//p' "${BASH_SOURCE[0]}"
         exit 0
         ;;
      *)
         printf "unknown flag: '%s'\\n" "$1" >&2
         exit 64
         ;;
   esac
done

if [ -z "${tool}" ]; then
   printf '%s\n' 'missing --tool' >&2
   exit 64
fi

if [ -z "${GITHUB_STEP_SUMMARY:-}" ]; then
   exit 0
fi

emit() {
   local row key val

   printf '## %s\n\n' "${tool}"
   if [ "${#rows[@]}" -gt 0 ]; then
      printf '| %s | count |\n' "${column_header}"
      printf '| --- | --- |\n'
      for row in "${rows[@]}"; do
         key="${row%%=*}"
         val="${row#*=}"
         printf '| %s | %s |\n' "${key}" "${val}"
      done
      printf '\n'
   fi
   if [ -n "${total}" ]; then
      printf '**Total: %s**\n\n' "${total}"
   fi
   if [ -n "${details_url}" ]; then
      printf '[Details](%s)\n\n' "${details_url}"
   fi
   if [ -n "${extra}" ]; then
      printf '%s\n\n' "${extra//|/$'\n'}"
   fi
}

emit >> "${GITHUB_STEP_SUMMARY}"
