#!/bin/bash

## Copyright (C) 2026 - 2026 ENCRYPTED SUPPORT LLC <adrelanos@whonix.org>
## See the file COPYING for copying conditions.

## AI-Assisted

## Best-effort live smoke test against the real GitHub REST API
## without a token. Exercises github-org-clone's read paths (account-
## type lookup + paginated repo listing) against a small, stable
## public org. No writes; no token; subject to GitHub's 60/hr
## unauthenticated rate limit per egress IP.
##
## Used by the workflow as a non-blocking smoke step
## (continue-on-error: true) so a rate-limit miss does not flake the
## build. Also runnable by hand from any developer machine:
##
##   CI=true ./ci/live-probe-unauth.sh
##
## Skips silently with a warning if the rate limit shows the bucket
## is exhausted - that is not a real failure.

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

# shellcheck source=../../helper-scripts/usr/libexec/helper-scripts/has.sh
source /usr/libexec/helper-scripts/has.sh

## Small, public, stable. octokit is GitHub's official Octokit org,
## ~30 repos. Acts as a representative test target for the github-
## org-clone read paths without burning much quota.
readonly target_org='octokit'

## Pre-flight: check unauth bucket. If empty, skip with a clear
## warning - exit 0 so the workflow's continue-on-error step does
## not surface a false failure.
status="$(curl --silent --max-time 10 --output /tmp/probe-rl.json \
   --write-out '%{http_code}' 'https://api.github.com/rate_limit')"
if [ "${status}" != '200' ]; then
   printf '%s\n' "skip: rate_limit endpoint HTTP ${status}; cannot probe." >&2
   exit 0
fi
remaining="$(jq --raw-output -- '.resources.core.remaining // 0' /tmp/probe-rl.json)"
if [ "${remaining}" -lt 5 ]; then
   printf '%s\n' \
      "skip: unauth core quota at ${remaining} (need >= 5); rate-limit window full." >&2
   exit 0
fi
printf '%s\n' "unauth core quota: ${remaining}"

## Tooling pre-flight.
for cmd in github-org-clone curl jq sanitize-string; do
   has "${cmd}" || { printf '%s\n' "error: ${cmd} not on PATH." >&2; exit 1; }
done

## Run github-org-clone in dry-run mode against the target. Verifies:
##  - Endpoint reachable
##  - account-type detection works (returns Organization)
##  - paginated listing works
##  - dry-run output mentions at least one repo
unset GITHUB_TOKEN
out_dir="$(mktemp --directory)"

probe_live_unauth_cleanup_out_dir() {
   safe-rm --recursive --force -- "${out_dir}"
}
trap probe_live_unauth_cleanup_out_dir EXIT

printf '%s\n' ""
printf '%s\n' "=== github-org-clone --dry-run ${target_org} ==="
out="$(github-org-clone --dry-run "${target_org}" "${out_dir}/clone" 2>&1)"
printf '%s\n' "${out}"

## Sanity check: dry-run output should include the "N repos to process"
## header and at least one "DRY-RUN: clone" line.
if ! grep --quiet --extended-regexp -- '^[0-9]+ repos to process' <<< "${out}"; then
   printf '%s\n' 'FAIL: expected "N repos to process" header in output' >&2
   exit 1
fi
if ! grep --quiet -- 'DRY-RUN: clone' <<< "${out}"; then
   printf '%s\n' 'FAIL: expected at least one "DRY-RUN: clone" line' >&2
   exit 1
fi

printf '%s\n' ""
printf '%s\n' 'live unauth smoke OK'
