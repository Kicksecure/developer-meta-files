#!/bin/bash

## Copyright (C) 2026 - 2026 ENCRYPTED SUPPORT LLC <adrelanos@whonix.org>
## See the file COPYING for copying conditions.

## AI-Assisted

## Thin wrapper around test_workflow_yaml.py. The validator logic
## itself lives in the .py file so it gets native tracebacks (with
## real line numbers), works with python tooling (pylint/mypy/
## pytest), and can be run standalone for debugging:
##
##   python3 ci/tests/test_workflow_yaml.py "$(git rev-parse --show-toplevel)"
##
## This .sh wrapper exists because the mock-test runner
## (ci/test-github-org-tools.sh) globs ci/tests/test_*.sh; the
## wrapper enforces the CI=true gate consistent with the other
## test_*.sh files in the suite and forwards the python script's
## exit code.

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

if ! command -v python3 >/dev/null 2>&1; then
   printf '%s\n' "${BASH_SOURCE[0]}: python3 not on PATH" >&2
   exit 2
fi

script_dir="$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" && pwd )"
repo_root="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"

exec python3 -- "${script_dir}/test_workflow_yaml.py" "${repo_root}"
