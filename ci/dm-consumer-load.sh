#!/bin/bash
## Copyright (C) 2026 - 2026 ENCRYPTED SUPPORT LLC <adrelanos@whonix.org>
## See the file COPYING for copying conditions.

## AI-Assisted

## Read a section of .github/dm-consumer.yml in the calling
## consumer repo and emit key=value lines to $GITHUB_OUTPUT for
## the reusable workflow to consume in subsequent steps.
##
## Usage:
##   dm-consumer-load.sh <section> <required-csv> <optional-csv>
##
## Required keys hard-fail on missing section, missing key,
## or empty value. Optional keys treat missing as empty (which
## downstream `if:` conditions interpret as "use the reusable's
## built-in default behavior"). Both reject embedded
## newlines / carriage returns ($GITHUB_OUTPUT format-injection
## mitigation).
##
## Hyphenated yml keys ('apt-packages') become underscored
## $GITHUB_OUTPUT names ('apt_packages'). GitHub Actions
## expression syntax parses `outputs.foo-bar` as subtraction;
## underscored names let downstream `if:` clauses use plain dot
## syntax (`steps.cfg.outputs.foo_bar`).
##
## Soft-skip when there are zero required keys AND the file or
## section is absent. This is the "universal-with-optional-
## overrides" case (e.g. consumer-codeql-python.yml where
## `codeql-python.prepare-command` is optional and most
## consumers omit it).
##
## Assumes yq is on PATH. The kislyuk python-yq syntax is used
## (`-r` for raw output, `// ""` for default). The reusable's
## prior step is expected to have apt-installed yq.

set -o errexit
set -o errtrace
set -o nounset
set -o pipefail
shopt -s inherit_errexit
shopt -s shift_verbose

if [ "$#" -ne 3 ]; then
   printf '%s\n' \
      "usage: dm-consumer-load.sh <section> <required-csv> <optional-csv>" >&2
   exit 64
fi

section="$1"
required_csv="$2"
optional_csv="$3"

cfg_file=".github/dm-consumer.yml"

emit_empty_for() {
   local keys_csv="$1"
   local key out_name
   local -a keys
   if [ -z "${keys_csv}" ]; then
      return 0
   fi
   IFS=',' read -ra keys <<< "${keys_csv}"
   for key in "${keys[@]}"; do
      out_name="${key//-/_}"
      printf '%s=\n' "${out_name}" >> "${GITHUB_OUTPUT}"
   done
}

read_key() {
   local key="$1" mode="$2"
   local value out_name
   value="$(yq -r ".\"${section}\".\"${key}\" // \"\"" "${cfg_file}")"
   if [ "${value}" = 'null' ]; then
      value=''
   fi
   if [ "${mode}" = 'required' ] && [ -z "${value}" ]; then
      printf '%s\n' "error: ${cfg_file} missing ${section}.${key}" >&2
      exit 1
   fi
   case "${value}" in
      *$'\n'*|*$'\r'*)
         printf '%s\n' "error: ${section}.${key} contains newline; not allowed" >&2
         exit 1
         ;;
   esac
   out_name="${key//-/_}"
   printf '%s=%s\n' "${out_name}" "${value}" >> "${GITHUB_OUTPUT}"
}

## Soft-skip if file or section absent AND no required keys.
if [ ! -f "${cfg_file}" ]; then
   if [ -n "${required_csv}" ]; then
      printf '%s\n' \
         "error: ${cfg_file} not found; section '${section}' requires: ${required_csv}" >&2
      exit 1
   fi
   emit_empty_for "${optional_csv}"
   exit 0
fi

section_value="$(yq -r ".\"${section}\" // \"\"" "${cfg_file}")"
if [ -z "${section_value}" ] || [ "${section_value}" = 'null' ]; then
   if [ -n "${required_csv}" ]; then
      printf '%s\n' \
         "error: ${cfg_file} missing section '${section}' (required: ${required_csv})" >&2
      exit 1
   fi
   emit_empty_for "${optional_csv}"
   exit 0
fi

if [ -n "${required_csv}" ]; then
   declare -a required_keys
   IFS=',' read -ra required_keys <<< "${required_csv}"
   for k in "${required_keys[@]}"; do
      read_key "${k}" 'required'
   done
fi

if [ -n "${optional_csv}" ]; then
   declare -a optional_keys
   IFS=',' read -ra optional_keys <<< "${optional_csv}"
   for k in "${optional_keys[@]}"; do
      read_key "${k}" 'optional'
   done
fi
