#!/bin/bash

## Copyright (C) 2026 - 2026 ENCRYPTED SUPPORT LLC <adrelanos@whonix.org>
## See the file COPYING for copying conditions.

## AI-Assisted

## Submit cov-int output to Coverity Scan.
##
## Expected env (from reusable-coverity.yml):
##   COVERITY_TOKEN
##   COVERITY_EMAIL
##   COVERITY_PROJECT
##   GITHUB_SHA          - identifies the snapshot in Coverity
##   GITHUB_RUN_NUMBER   - human-readable run identifier
##   GITHUB_REF_NAME     - branch / tag name
##   DRY_RUN             - optional. When 'true', pack cov-int.tgz
##                         but skip the scan.coverity.com submission.
##                         Useful for exercising the full pipeline
##                         (download, verify, build, archive) without
##                         consuming the daily submission slot. The
##                         cov-int.tgz artifact still uploads.
##
## Cwd contract: caller runs this with the consumer repo checkout as
## cwd; ./cov-int/ is the build output created by the build step.

set -o errexit
set -o nounset
set -o pipefail
set -o errtrace
shopt -s inherit_errexit
shopt -s shift_verbose

## CI guard. Submits to scan.coverity.com using a repo secret.
## Refuse outside CI unless ALLOW_LOCAL=true is set explicitly.
if [ "${CI:-}" != "true" ] && [ "${ALLOW_LOCAL:-}" != "true" ]; then
  printf '%s\n' "${BASH_SOURCE[0]}: refusing to run outside CI (CI != 'true'). Set ALLOW_LOCAL=true to override." >&2
  exit 1
fi

tar -czf cov-int.tgz -- cov-int

if [ "${DRY_RUN:-false}" = 'true' ]; then
  printf '%s\n' "DRY RUN: skipping scan.coverity.com submission."
  printf '%s\n' "  project: ${COVERITY_PROJECT}"
  printf '%s\n' "  version: ${GITHUB_SHA:-unknown}"
  printf '%s\n' "  description: GHA run ${GITHUB_RUN_NUMBER:-unknown} on ${GITHUB_REF_NAME:-unknown}"
  printf '%s\n' "  archive: $(stat -c '%s' -- cov-int.tgz) bytes"
  printf '%s\n' "cov-int.tgz still uploads via the always-upload artifact step."
  exit 0
fi

curl \
  --silent \
  --show-error \
  --fail \
  --form "token=${COVERITY_TOKEN}" \
  --form "email=${COVERITY_EMAIL}" \
  --form "file=@cov-int.tgz" \
  --form "version=${GITHUB_SHA:-unknown}" \
  --form "description=GHA run ${GITHUB_RUN_NUMBER:-unknown} on ${GITHUB_REF_NAME:-unknown}" \
  "https://scan.coverity.com/builds?project=${COVERITY_PROJECT}"

printf '%s\n' "Submission accepted by scan.coverity.com."
printf '%s\n' "Results will appear at: https://scan.coverity.com/projects/${COVERITY_PROJECT}"
