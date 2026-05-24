#!/bin/bash
## Copyright (C) 2026 - 2026 ENCRYPTED SUPPORT LLC <adrelanos@whonix.org>
## See the file COPYING for copying conditions.

## AI-Assisted

## Emit a NUL-separated list of Python source files in the
## current working directory, discovered by either:
##
##   - `.py` filename extension, OR
##   - first-line shebang matching '^#!.*python'
##
## The shebang scan catches genmkfile-tagged Python files
## ('*.py#package-tag') and Debian-libexec-style scripts without
## any extension - common across this org (security-misc,
## msgcollector, helper-scripts, developer-meta-files itself).
##
## Excludes:
##
##   - .git/
##   - .github/dmf/ (the dmf orchestration checkout that the
##     calling workflow stages alongside the consumer source)
##   - Submodule directories (paths read from .gitmodules)
##
## Intended for bandit and similar tools that take an explicit
## file list rather than directory-recursive walking. Output is
## suitable for `xargs -0 --no-run-if-empty -- bandit -- ...`.
##
## Exit code is 0 on success; non-zero only on I/O / parse
## errors. An empty Python tree is success with zero output.

set -o errexit
set -o errtrace
set -o nounset
set -o pipefail
shopt -s inherit_errexit
shopt -s shift_verbose

## Base find excludes.
exclude_args=(
   -not -path './.git/*'
   -not -path './.github/dmf/*'
)

## Append submodule paths from .gitmodules if present. Each
## submodule.<id>.path entry becomes an exclude.
if [ -f .gitmodules ]; then
   while IFS= read -r line; do
      ## line is 'submodule.<id>.path<NUL><path>'.
      case "${line}" in
         *path*)
            sub_path="${line#*$'\n'}"
            if [ -n "${sub_path}" ]; then
               exclude_args+=( -not -path "./${sub_path}/*" )
            fi
            ;;
      esac
   done < <(git config -z --file .gitmodules --get-regexp 'submodule\..*\.path' 2>/dev/null || true)
fi

## Stage 1: files with .py extension.
find . -type f "${exclude_args[@]}" -name '*.py' -print0

## Stage 2: files without .py extension whose first line matches
## a python shebang. Read only the first 256 bytes to avoid
## scanning large binaries.
##
## WARNING: Loop runs in a subshell due to having information piped
## into it.
find . -type f "${exclude_args[@]}" -not -name '*.py' -print0 \
   | while IFS= read -r -d '' f; do
      first_line=$(head -c 256 -- "${f}" 2>/dev/null | head -n 1 || true)
      case "${first_line}" in
         '#!'*python*)
            printf '%s\0' "${f}"
            ;;
      esac
   done
