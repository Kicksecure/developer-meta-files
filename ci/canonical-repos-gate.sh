#!/bin/bash

## Copyright (C) 2026 - 2026 ENCRYPTED SUPPORT LLC <adrelanos@whonix.org>
## See the file COPYING for copying conditions.

## AI-Assisted

## Step-level canonical-repos gate. Emits `allowed=true|false`
## to $GITHUB_OUTPUT based on whether ${THIS_REPO} is in the
## comma-separated ${CANONICAL_REPOS} list.
##
## Expected env:
##   CANONICAL_REPOS - comma-separated 'owner/repo' list
##                     (typically from steps.cfg.outputs.canonical_repos)
##   THIS_REPO       - the current repository (github.repository)
##
## Strict by design: workflow_dispatch does NOT bypass. A fork-
## side manual dispatch would burn runner time for nothing (org
## secrets are not available to forks) and the canonical's
## quota is therefore never at risk from cross-fork manual
## triggers.
##
## Used by reusable-coverity.yml after the dm-consumer.yml
## load step. Subsequent expensive steps (cov-download / build /
## submit) gate on `steps.gate.outputs.allowed == 'true'`.

set -o errexit
set -o errtrace
set -o nounset
set -o pipefail
shopt -s inherit_errexit
shopt -s shift_verbose

if printf ',%s,' "${CANONICAL_REPOS}" | grep --fixed-strings --quiet -- ",${THIS_REPO},"; then
   printf '%s\n' \
      "gate: ${THIS_REPO} is canonical (in '${CANONICAL_REPOS}'); allowing" >&2
   printf 'allowed=true\n' >> "${GITHUB_OUTPUT}"
else
   printf '%s\n' \
      "gate: ${THIS_REPO} is not canonical (list: '${CANONICAL_REPOS}'); skipping expensive steps" >&2
   printf 'allowed=false\n' >> "${GITHUB_OUTPUT}"
fi
