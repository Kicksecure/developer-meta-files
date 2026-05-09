#!/bin/bash

## Copyright (C) 2026 - 2026 ENCRYPTED SUPPORT LLC <adrelanos@whonix.org>
## See the file COPYING for copying conditions.

## AI-Assisted

## Pin the failure path of die_if_not_has from helper-scripts'
## log_run_die.sh. dm-github-org-policy and dm-github-fork-sync use
## it to bail out at script-init time when github-org-fork is not
## on PATH. Test invokes the script with PATH stripped so the
## binary is missing.
##
## The check is structurally important: a missing prerequisite must
## fail closed (non-zero exit) and name the missing command so the
## operator knows what to install. A future refactor that swaps
## die_if_not_has for a soft warning would silently apply policy
## using a wrong-command surface, which is the failure mode this
## test guards against.

set -o errexit
set -o nounset
set -o pipefail
set -o errtrace
shopt -s inherit_errexit
shopt -s shift_verbose

if [ "${CI:-}" != "true" ]; then
   printf '%s\n' \
      'error: this script must run with CI=true (GitHub Actions or equivalent).' >&2
   exit 1
fi

fail=0
rc=0

## Build a minimal PATH directory that contains every helper-scripts
## tool the script needs (stecho, sanitize-string for log_run_die.sh's
## hard-tools check) but NOT github-org-fork. Run dm-github-org-policy
## via absolute path with PATH set to that minimal dir ONLY -
## NOT /usr/bin or /bin. The CI workflow runs `genmkfile install`
## before this test, which puts github-org-fork into /usr/bin; on
## merged-/usr distros (Debian trixie) /bin -> /usr/bin so excluding
## /usr/bin alone is not enough. die_if_not_has fires on the first
## 'has github-org-fork || die ...' inside the script.
##
## env -i strips the inherited environment so a stale PATH cannot
## leak through; HELPER_SCRIPTS_PATH is re-injected because the
## script sources lib files from there at startup.
bin="$(command -v dm-github-org-policy)"
[ -n "${bin}" ] || { printf '%s\n' "FAIL: dm-github-org-policy not on the test PATH" >&2; exit 1; }

minpath_dir="$(mktemp --directory)"
trap 'rm -r -f -- "${minpath_dir}"' EXIT
ln -s -- "$(command -v stecho)"          "${minpath_dir}/stecho"
ln -s -- "$(command -v sanitize-string)" "${minpath_dir}/sanitize-string"

out="$(env -i \
   HELPER_SCRIPTS_PATH="${HELPER_SCRIPTS_PATH:-/usr}" \
   PATH="${minpath_dir}" \
   "${bin}" --dry-run 2>&1)" || rc=$?

if [ "${rc}" -eq 0 ]; then
   printf '%s\n' "FAIL: dm-github-org-policy with restricted PATH succeeded; expected failure (github-org-fork missing)" >&2
   printf '%s\n' "${out}" >&2
   fail=1
fi

## Message must name the missing command so the operator can act.
required=( 'github-org-fork' 'not found' )
for needle in "${required[@]}"; do
   if ! grep --quiet --fixed-strings -- "${needle}" <<< "${out}"; then
      printf '%s\n' "FAIL: missing fragment in die_if_not_has output: ${needle}" >&2
      fail=1
   fi
done

exit "${fail}"
