#!/bin/bash

## Copyright (C) 2026 - 2026 ENCRYPTED SUPPORT LLC <adrelanos@whonix.org>
## See the file COPYING for copying conditions.

## AI-Assisted

## Composite-action implementation: walk the configured paths,
## identify shell scripts by FIRST-LINE shebang, run shellcheck.
##
## Discovery is shebang-based (not file-extension or hardcoded list)
## so every Debian libexec-style executable (no extension) gets
## linted automatically; new scripts get linted without touching
## the workflow.
##
## Recognized shebangs: bash | sh | dash | ksh, both direct
## (#!/bin/bash) and via env (#!/usr/bin/env bash).

set -o errexit
set -o nounset
set -o pipefail
set -o errtrace
shopt -s inherit_errexit
shopt -s shift_verbose

if [ "${CI:-}" != "true" ] && [ "${ALLOW_LOCAL:-}" != "true" ]; then
   printf '%s\n' \
      "${BASH_SOURCE[0]}: refusing to run outside CI. Set ALLOW_LOCAL=true to override." >&2
   exit 1
fi

cd -- "$(git rev-parse --show-toplevel)"

## Shebang matcher. Hits:
##   #!/bin/bash, #!/bin/sh, #!/bin/dash, #!/bin/ksh
##   #!/usr/local/bin/<any of above>
##   #!/usr/bin/env bash, #!/usr/bin/env sh, etc.
## Rejects:
##   #!/usr/bin/python3 - no shell name in interpreter path.
##   #!/bin/csh         - 'csh' is not in the alternation, and 'sh'
##                        is not preceded by a path separator '/'.
shellbang_re='^#![[:space:]]*([^[:space:]]+/)?(bash|sh|dash|ksh)([[:space:]]|$)|^#![[:space:]]*[^[:space:]]+/env[[:space:]]+(bash|sh|dash|ksh)([[:space:]]|$)'

files=()
while IFS= read -r -d '' candidate; do
   ## First-line read; bail if empty or unreadable.
   read -r first_line < "${candidate}" || continue
   if [[ "${first_line}" =~ $shellbang_re ]]; then
      files+=( "${candidate}" )
   fi
done < <(
   ## SC_PATHS is space-separated; intentional word-splitting.
   ## shellcheck disable=SC2086
   find ${SC_PATHS} -type f -print0 2>/dev/null
)

if [ "${#files[@]}" -eq 0 ]; then
   printf '%s\n' "shellcheck: no shell scripts discovered under: ${SC_PATHS}"
   exit 0
fi

shellcheck_args=( --severity="${SC_SEVERITY}" )
if [ -n "${SC_EXCLUDES}" ]; then
   shellcheck_args+=( "--exclude=${SC_EXCLUDES}" )
fi
if [ -n "${SC_SHELL}" ]; then
   shellcheck_args+=( "--shell=${SC_SHELL}" )
fi

exit_code=0
for file_name in "${files[@]}"; do
   printf '%s\n' "Checking: ${file_name}"
   shellcheck "${shellcheck_args[@]}" -- "${file_name}" || exit_code=1
done

printf '%s\n' "shellcheck: ${#files[@]} file(s) scanned"
exit "${exit_code}"
