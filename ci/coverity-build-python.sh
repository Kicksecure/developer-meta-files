#!/bin/bash

## Copyright (C) 2026 - 2026 ENCRYPTED SUPPORT LLC <adrelanos@whonix.org>
## See the file COPYING for copying conditions.

## AI-Assisted

## Default cov-build invocation for Python-only repositories.
##
## --no-command + --fs-capture-search means "do not invoke a real
## build, just walk the filesystem and ingest source files". This is
## the documented Coverity approach for interpreted-only projects.
## C / C++ / Go / etc. consumers must supply their own build-command
## input to the reusable workflow instead of relying on this script.
##
## Cwd contract: caller runs this with the consumer repo checkout as
## cwd. cov-build is invoked via the deterministic path under
## ./cov-analysis/ (created by ci/coverity-download.sh).

set -o errexit
set -o nounset
set -o pipefail
set -o errtrace

## CI guard. Requires ./cov-analysis/bin/cov-build (set up by
## coverity-download.sh). Refuse outside CI unless ALLOW_LOCAL=true
## is set explicitly.
if [ "${CI:-}" != "true" ] && [ "${ALLOW_LOCAL:-}" != "true" ]; then
  printf '%s\n' "${BASH_SOURCE[0]}: refusing to run outside CI (CI != 'true'). Set ALLOW_LOCAL=true to override." >&2
  exit 1
fi

./cov-analysis/bin/cov-build \
  --dir cov-int \
  --no-command \
  --fs-capture-search "${PWD}" \
  --fs-capture-search-exclude-regex '/\.git(/|$)|/cov-analysis(/|$)|/cov-int(/|$)'

printf '%s\n' "::group::cov-int build summary"
tail -n 100 -- cov-int/build-log.txt 2>/dev/null || true
printf '%s\n' "::endgroup::"
