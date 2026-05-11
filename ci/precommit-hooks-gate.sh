#!/bin/bash

## Copyright (C) 2026 - 2026 ENCRYPTED SUPPORT LLC <adrelanos@whonix.org>
## See the file COPYING for copying conditions.

## AI-Assisted

## Run the curated hook set from misc/pre-commit-config.yaml
## against files changed in HEAD vs the base ref ($1, default
## origin/master).
##
## Uses the upstream 'pre-commit' framework as the runner because
## it correctly dispatches each hook to its declared file-type
## subset (types: [text], types: [yaml], types: [executable], ...).
## The earlier hand-rolled bash version of this gate passed the
## full changed-file list to every hook, which broke
## 'check-executables-have-shebangs' (it then flagged every text
## file as needing a shebang). Letting the framework do the
## filtering is shorter, correct, and matches what local-hook
## adoption would use too.
##
## Hooks SKIPped here (set via SKIP env var, comma-separated):
##   no-commit-to-branch    pre-commit-stage hook; CI runs after
##                          the commit and would also fail the
##                          push-to-master trigger pointlessly.
##
## Other hooks restricted to non-CI stages by the config itself
## (unicode-merged-ref's 'stages: [pre-merge-commit, manual]') do
## NOT need explicit skipping; pre-commit honors stages: filters.
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

note() {
   printf '%s\n' "precommit-hooks: ${1}" >&2
}

note "running pre-commit framework against ${base_ref}...HEAD"
SKIP='no-commit-to-branch' \
   pre-commit run \
      --config misc/pre-commit-config.yaml \
      --from-ref "${base_ref}" \
      --to-ref HEAD
