#!/bin/bash

## Copyright (C) 2026 - 2026 ENCRYPTED SUPPORT LLC <adrelanos@whonix.org>
## See the file COPYING for copying conditions.

## AI-Assisted

## Append a markdown panel to ${GITHUB_STEP_SUMMARY}. Defaults to
## /dev/null when unset so callers can invoke unconditionally.
##
## R-093: self-contained (no helper-scripts source) so the script
## runs from workflow steps that haven't installed helper-scripts.
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
## --row repeats; column header defaults to 'item'. --extra is one
## string with '|'-separated lines.

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

## FIXME: This function is named as if it will print usage information, but
## doesn't.
die_usage() {
   printf '%s\n' "$1" >&2
   exit 64
}

while [ "$#" -gt 0 ]; do
   case "$1" in
      --tool)
         [ "$#" -ge 2 ] || die_usage 'missing value for --tool'
         tool="$2"
         shift 2
         ;;
      --column-header)
         [ "$#" -ge 2 ] || die_usage 'missing value for --column-header'
         column_header="$2"
         shift 2
         ;;
      --row)
         [ "$#" -ge 2 ] || die_usage 'missing value for --row'
         ## FIXME: Either rename this variable to 'row', or rename the option
         ## to '--rows', the naming is confusing.
         rows+=( "$2" )
         shift 2
         ;;
      --total)
         [ "$#" -ge 2 ] || die_usage 'missing value for --total'
         total="$2"
         shift 2
         ;;
      --details-url)
         [ "$#" -ge 2 ] || die_usage 'missing value for --details-url'
         details_url="$2"
         shift 2
         ;;
      --extra)
         [ "$#" -ge 2 ] || die_usage 'missing value for --extra'
         extra="$2"
         shift 2
         ;;
      --)
         shift
         break
         ;;
      -h|--help)
         ## FIXME: Implement a proper 'print_usage' function that prints a
         ## string that replaces the comments. Do not extract help information
         ## from script-embedded comments. Do not duplicate the same text in
         ## both comments and help text. See Bash style guide R-153.
         sed --quiet -- 's/^## \{0,1\}//p' "${BASH_SOURCE[0]}"
         exit 0
         ;;
      *)
         die_usage "unknown flag: '$1'"
         ;;
   esac
done

[ -n "${tool}" ] || die_usage 'missing --tool'

## Default to /dev/null so callers invoke unconditionally.
[[ -v GITHUB_STEP_SUMMARY ]] || GITHUB_STEP_SUMMARY='/dev/null'

emit() {
   local row key val extra_with_nl
   local -a parts=()

   parts+=( "## ${tool}" "" )
   if [ "${#rows[@]}" -gt 0 ]; then
      parts+=( "| ${column_header} | count |" "| --- | --- |" )
      for row in "${rows[@]}"; do
         key="${row%%=*}"
         val="${row#*=}"
         parts+=( "| ${key} | ${val} |" )
      done
      parts+=( "" )
   fi
   [ -n "${total}" ] && parts+=( "**Total: ${total}**" "" )
   [ -n "${details_url}" ] && parts+=( "[Details](${details_url})" "" )
   if [ -n "${extra}" ]; then
      extra_with_nl="${extra//|/$'\n'}"
      parts+=( "${extra_with_nl}" "" )
   fi

   printf '%s\n' "${parts[@]}"
}

emit >> "${GITHUB_STEP_SUMMARY}"
