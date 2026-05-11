#!/bin/bash

## Copyright (C) 2026 - 2026 ENCRYPTED SUPPORT LLC <adrelanos@whonix.org>
## See the file COPYING for copying conditions.

## AI-Assisted

## Run the curated 'pre-commit-hooks' binary set against files
## changed in HEAD vs the base ref ($1, default 'origin/master').
## Bare-binary invocations (no pre-commit framework dependency).
##
## Per-hook file-type filtering is done locally in this script
## rather than delegated to the framework. Each hook gets the
## subset its upstream 'types:' declaration would have selected:
##   * filename-blind (any file)        check-added-large-files,
##                                      check-case-conflict,
##                                      destroyed-symlinks,
##                                      forbid-new-submodules
##   * text                             check-merge-conflict,
##                                      check-vcs-permalinks,
##                                      detect-aws-credentials,
##                                      detect-private-key,
##                                      fix-byte-order-marker,
##                                      end-of-file-fixer,
##                                      trailing-whitespace-fixer,
##                                      mixed-line-ending,
##                                      check-shebang-scripts-are-executable
##   * text AND executable              check-executables-have-shebangs
##   * symlink                          check-symlinks
##   * type by extension (yml/json/     check-yaml, check-json, check-toml,
##     toml/xml/python/req-files)       check-xml, check-ast,
##                                      check-builtin-literals,
##                                      debug-statement-hook,
##                                      double-quote-string-fixer,
##                                      pretty-format-json,
##                                      requirements-txt-fixer
##
## Hooks NOT run vs the dm-precommit-bare draft list / vs
## misc/pre-commit-config.yaml, with reasons:
##   no-commit-to-branch     pre-commit-stage hook; CI runs after
##                           the commit and the push-to-master
##                           trigger would fail pointlessly.
##   unicode-merged-ref      stages: [pre-merge-commit, manual] only
##   name-tests-test         dmf has no Python tests/ dir using the
##                           enforced naming convention; would no-op.
##   file-contents-sorter    files: '^$' in the config (opt-in only)
##   sort-simple-yaml        same
##   fix-encoding-pragma     deprecated upstream; dropped from
##                           misc/pre-commit-config.yaml already
##
## Style-guide deviations, documented for reviewers:
##   * R-040 (log not printf): self-contained CI tool; runs on a
##     fresh runner without helper-scripts on PATH. Same R-093
##     spirit as agents/pre-push-static.sh.

set -o errexit
set -o nounset
set -o pipefail
set -o errtrace
shopt -s inherit_errexit
shopt -s shift_verbose

if [ "$#" -ge 1 ] && [ -n "${1}" ]; then
   base_ref="${1}"
else
   base_ref='origin/master'
fi
fail_count=0

note() {
   printf '%s\n' "precommit-hooks: ${1}" >&2
}

fail() {
   note "FAIL ${1}"
   fail_count=$((fail_count + 1))
}

is_text_file() {
   ## Cheap extension match first; fall back to file --mime for
   ## files lacking a known extension (e.g. shell scripts named
   ## 'foo' with a shebang, or POSIX-style man pages).
   local f mime
   f="${1}"
   case "${f}" in
      *.md|*.sh|*.bsh|*.bash|*.py|*.yml|*.yaml|*.json|*.toml \
      |*.xml|*.txt|*.csv|*.cfg|*.conf|*.ini|*.rst|*.html|*.css \
      |*.js|*.ts|*.c|*.h|*.cpp|*.hpp|*.go|*.rs|*.tex|*.dockerfile \
      |Dockerfile|Makefile|COPYING|README|LICENSE)
         return 0
         ;;
   esac
   mime="$(file --brief --mime --dereference -- "${f}" 2>/dev/null || true)"
   case "${mime}" in
      text/* \
      |*x-shellscript* \
      |*x-python* \
      |*json* \
      |*xml* \
      |*yaml* \
      |*toml* \
      |*charset=us-ascii* \
      |*charset=utf-8*)
         return 0
         ;;
   esac
   return 1
}

run_hook() {
   local hook
   hook="${1}"
   shift
   if [ "$#" -eq 0 ]; then
      return 0
   fi
   "${hook}" "${@}" || fail "${hook}"
}

main() {
   local f
   local -a all_files text_files exec_text_files \
            symlink_files yaml_files json_files toml_files \
            xml_files python_files req_files

   all_files=()
   text_files=()
   exec_text_files=()
   symlink_files=()
   yaml_files=()
   json_files=()
   toml_files=()
   xml_files=()
   python_files=()
   req_files=()

   while IFS= read -r f; do
      if [ -z "${f}" ]; then
         continue
      fi
      ## Drop deleted/renamed paths that no longer exist (paranoia;
      ## --diff-filter=ACMRT excludes D but a rename's old name can
      ## still vanish from the working tree).
      if [ ! -e "${f}" ]; then
         continue
      fi
      all_files+=("${f}")
      if [ -L "${f}" ]; then
         symlink_files+=("${f}")
         ## Symlinks aren't text; skip the text/executable buckets.
         continue
      fi
      if is_text_file "${f}"; then
         text_files+=("${f}")
         if [ -x "${f}" ] && [ -f "${f}" ]; then
            exec_text_files+=("${f}")
         fi
      fi
      case "${f}" in
         *.yml|*.yaml) yaml_files+=("${f}") ;;
         *.json)       json_files+=("${f}") ;;
         *.toml)       toml_files+=("${f}") ;;
         *.xml)        xml_files+=("${f}") ;;
         *.py)         python_files+=("${f}") ;;
      esac
      case "${f}" in
         requirements*.txt|constraints*.txt \
         |*/requirements*.txt|*/constraints*.txt)
            req_files+=("${f}")
            ;;
      esac
   done < <(git diff --name-only --diff-filter=ACMRT "${base_ref}"...HEAD)

   if [ "${#all_files[@]}" -eq 0 ]; then
      note "no changed files; nothing to check"
      return 0
   fi

   ## Filename-blind hooks (run on every changed path):
   run_hook check-added-large-files                            "${all_files[@]}"
   run_hook check-case-conflict                                "${all_files[@]}"
   run_hook destroyed-symlinks                                 "${all_files[@]}"
   run_hook forbid-new-submodules                              "${all_files[@]}"

   ## text-only:
   run_hook check-merge-conflict                               "${text_files[@]}"
   run_hook check-vcs-permalinks                               "${text_files[@]}"
   run_hook detect-aws-credentials --allow-missing-credentials "${text_files[@]}"
   run_hook detect-private-key                                 "${text_files[@]}"
   run_hook fix-byte-order-marker                              "${text_files[@]}"
   run_hook end-of-file-fixer                                  "${text_files[@]}"
   run_hook trailing-whitespace-fixer                          "${text_files[@]}"
   run_hook mixed-line-ending --fix=no                         "${text_files[@]}"
   run_hook check-shebang-scripts-are-executable               "${text_files[@]}"

   ## text AND executable:
   run_hook check-executables-have-shebangs                    "${exec_text_files[@]}"

   ## symlinks:
   run_hook check-symlinks                                     "${symlink_files[@]}"

   ## type by extension:
   run_hook check-yaml                "${yaml_files[@]}"
   run_hook check-json                "${json_files[@]}"
   run_hook check-toml                "${toml_files[@]}"
   run_hook check-xml                 "${xml_files[@]}"
   run_hook check-ast                 "${python_files[@]}"
   run_hook check-builtin-literals    "${python_files[@]}"
   run_hook debug-statement-hook      "${python_files[@]}"
   run_hook double-quote-string-fixer "${python_files[@]}"
   run_hook pretty-format-json        "${json_files[@]}"
   run_hook requirements-txt-fixer    "${req_files[@]}"

   if [ "${fail_count}" -gt 0 ]; then
      note "${fail_count} hook(s) failed"
      exit 1
   fi
   note "all hooks passed"
}

main "${@}"
