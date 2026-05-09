#!/bin/bash

## Copyright (C) 2026 - 2026 ENCRYPTED SUPPORT LLC <adrelanos@whonix.org>
## See the file COPYING for copying conditions.

## AI-Assisted

## Mock-API test: dm-github-org-policy --audit produces a report with the
## per-org settings sections, members lacking 2FA, rulesets, PAT
## activity, installed Apps - all read-only, no PATCH/PUT/POST.

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

SCRIPT_DIR="$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" && pwd )"
FIXTURE_DIR="$(cd -- "${SCRIPT_DIR}/../fixtures" && pwd)"

export GHORG_MOCK=1
export GHORG_MOCK_DIR="${FIXTURE_DIR}"

out="$(dm-github-org-policy --audit 2>&1)"

fail=0
required=(
   '=== audit: org-ai-assisted ==='
   'fork-PR approval policy: first_time_contributors'
   'workflow GITHUB_TOKEN permissions: default=write'
   'actions allowed_actions: enabled_repos=all, allowed_actions=all'
   '2FA required for org members: false'
   'code-security defaults for new repos:'
   'members lacking 2FA'
   'existing rulesets named'
   'fine-grained PAT activity:'
   'installed GitHub Apps:'
   'org webhooks (Scorecard "Webhooks" check):'
   'total=2, lacking secret=1'
   'dependabot.yml presence (Scorecard "Dependency-Update-Tool"):'
   ## After dm-github-org-policy switched to inc_forks=1, the fork
   ## repo (some-fork) is also enumerated by the dependabot.yml
   ## audit. Fixture has the file for derivative-maker only;
   ## helper-scripts AND some-fork register as missing.
   'have=1, missing=2'
   '    - org-ai-assisted/helper-scripts'
   '    - org-ai-assisted/some-fork'
)

for needle in "${required[@]}"; do
   if ! grep --quiet --fixed-strings -- "${needle}" <<< "${out}"; then
      printf '%s\n' "FAIL: missing expected fragment: ${needle}" >&2
      fail=1
   fi
done

## Audit must NEVER print DRY-RUN: prefixes (those are apply-mode).
if grep --quiet -- 'DRY-RUN:' <<< "${out}"; then
   printf '%s\n' 'FAIL: --audit unexpectedly printed DRY-RUN: lines' >&2
   fail=1
fi

exit "${fail}"
