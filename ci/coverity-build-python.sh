#!/bin/bash

## Copyright (C) 2026 - 2026 ENCRYPTED SUPPORT LLC <adrelanos@whonix.org>
## See the file COPYING for copying conditions.

## AI-Assisted

## Default 'coverity capture' invocation for Python-only repositories.
##
## Uses the Coverity CLI's buildless capture, included in the free
## scan.coverity.com tarball as ./cov-analysis/bin/coverity since
## the 2024.12 tool generation. Replaces the legacy
## 'cov-build --no-command --fs-capture-search' flow which the
## current free-tier 'Coverity Build Capture' tool no longer
## accepts (verified empirically: --no-command and
## --fs-capture-search both reject as 'Undefined option').
##
## C / C++ / Go / etc. consumers must supply their own
## build-command input to the reusable workflow instead of relying
## on this script.
##
## Cwd contract: caller runs this with the consumer repo checkout
## as cwd. 'coverity' is invoked via the deterministic path under
## ./cov-analysis/ (created by ci/coverity-download.sh).

set -o errexit
set -o nounset
set -o pipefail
set -o errtrace
## FIXME: Why aren't the shopt settings here?

## CI guard. Requires ./cov-analysis/bin/coverity (set up by
## coverity-download.sh). Refuse outside CI unless ALLOW_LOCAL=true
## is set explicitly.
if [ "${CI:-}" != "true" ] && [ "${ALLOW_LOCAL:-}" != "true" ]; then
  printf '%s\n' "${BASH_SOURCE[0]}: refusing to run outside CI (CI != 'true'). Set ALLOW_LOCAL=true to override." >&2
  exit 1
fi

## --language python: emit only Python sources via the buildless
## capture path (cov-internal-python3-fe under the hood). Add more
## --language flags here if a Python repo also has JS / TS / etc.
## sources worth scanning.
## --file-exclude-regex: skip cov-analysis (the downloaded tool
## itself), cov-int (this run's intermediate dir), and .git
## metadata. Regex is applied to repo-relative paths.
./cov-analysis/bin/coverity capture \
  --project-dir "${PWD}" \
  --dir cov-int \
  --language python \
  --file-exclude-regex 'cov-analysis/.*|cov-int/.*|\.git/.*'

printf '%s\n' "::group::cov-int build summary"
tail -n 100 -- cov-int/build-log.txt 2>/dev/null || true
printf '%s\n' "::endgroup::"
