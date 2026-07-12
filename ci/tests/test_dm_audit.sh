#!/bin/bash

## Copyright (C) 2026 - 2026 ENCRYPTED SUPPORT LLC <adrelanos@whonix.org>
## See the file COPYING for copying conditions.

## AI-Assisted

## Mock-API test: dm-github-org-policy --audit produces a report with the
## per-org settings sections, members lacking 2FA, rulesets, PAT
## activity, installed Apps - all read-only, no PATCH/PUT/POST.
##
## Both the PRESENCE of each required substring AND its ORDER relative to
## the others are asserted. Order matters because a silent section
## reorder (e.g. PAT activity printed before code-security defaults) is
## otherwise invisible to substring-only assertions, yet would change
## the meaning a maintainer reads off the audit output. The walker walks
## the audit output once and advances through the required[] list
## monotonically; a needle that is missing, duplicated upstream of its
## intended position, or moved after a later section, all surface as the
## same 'not found in order' failure - which is fine because every one
## of those is an audit-format regression to investigate.

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
FIXTURES_DIR="$(cd -- "${SCRIPT_DIR}/../fixtures" && pwd)"

export GHORG_MOCK=true
export GHORG_MOCK_DIR="${FIXTURES_DIR}"

out="$(ORGS_OVERRIDE='org-ai-assisted' dm-github-org-policy --audit 2>&1)"

fail=0
## NOTE: order in this array must match the chronological output order
## of audit_org_state() in usr/bin/dm-github-org-policy. The walker
## below enforces it.
required=(
   '=== audit: org-ai-assisted ==='
   'fork-PR approval policy: first_time_contributors'
   'workflow GITHUB_TOKEN permissions: default=write'
   'actions allowed_actions: enabled_repos=all, allowed_actions=all'
   '2FA required for org members: false'
   'code-security defaults for new repos:'
   'members lacking 2FA'
   ## 'existing rulesets named' and 'fine-grained PAT activity:'
   ## sections are commented out in usr/bin/dm-github-org-policy
   ## (org-level rulesets are Team+ only; PAT-activity endpoints are
   ## GitHub-App-only - both unreachable from this PAT-based tool).
   ## Restore both assertions if either block is uncommented.
   'installed GitHub Apps:'
   'org webhooks (Scorecard "Webhooks" check):'
   'total=2, lacking secret=1'
   ## Private-repo audit: the GET_orgs_..._repos fixture has
   ## private-thing (private, non-archived) plus public/archived/
   ## fork siblings. Only private-thing should appear under the
   ## new private-repo header. The mock dispatcher strips the
   ## ?type=private query, so the audit's client-side
   ## .private == true filter is what makes the test meaningful.
   'private repos (would lose secret-scan + push-protection on Free without GHAS):'
   '    - org-ai-assisted/private-thing'
   'dependabot.yml presence (Scorecard "Dependency-Update-Tool"):'
   ## After dm-github-org-policy switched to inc_forks=1, the fork
   ## repo (some-fork) is also enumerated by the dependabot.yml
   ## audit. Fixture has the file for derivative-maker only;
   ## helper-scripts AND some-fork register as missing. Output
   ## format is per-repo 'yes:' / 'no:' lines + a 'summary:' line.
   ## Per-repo lines are emitted in 'sort --unique' order
   ## (alphabetical: derivative-maker < helper-scripts < some-fork),
   ## then the summary line.
   '    yes: org-ai-assisted/derivative-maker'
   '    no:  org-ai-assisted/helper-scripts'
   '    no:  org-ai-assisted/some-fork'
   '    summary: have=1, missing=2'
)

## Order-preserving walker. Each required[i] must appear on a line at
## or after where required[i-1] was matched. Walks output once.
mapfile -t out_lines <<< "${out}"
needle_idx=0
last_match_line=0
while [ "${needle_idx}" -lt "${#required[@]}" ]; do
   line_idx="${last_match_line}"
   matched=0
   while [ "${line_idx}" -lt "${#out_lines[@]}" ]; do
      if [[ "${out_lines[line_idx]}" == *"${required[needle_idx]}"* ]]; then
         last_match_line=$(( line_idx + 1 ))
         matched=1
         break
      fi
      line_idx=$(( line_idx + 1 ))
   done
   if [ "${matched}" -eq 0 ]; then
      ## Distinguish 'missing entirely' (not anywhere in output) from
      ## 'out of order' (present, but before the current cursor).
      if grep --quiet --fixed-strings -- "${required[needle_idx]}" <<< "${out}"; then
         printf '%s\n' "FAIL: out-of-order fragment: '${required[needle_idx]}'" \
            "       (present in output but before line ${last_match_line};" \
            "        previous match was '${required[needle_idx - 1]:-<start>}' on line ${last_match_line})" >&2
      else
         printf '%s\n' "FAIL: missing expected fragment: '${required[needle_idx]}'" >&2
      fi
      fail=1
   fi
   needle_idx=$(( needle_idx + 1 ))
done

## Audit must NEVER print DRY-RUN: prefixes (those are apply-mode).
if grep --quiet -- 'DRY-RUN:' <<< "${out}"; then
   printf '%s\n' 'FAIL: --audit unexpectedly printed DRY-RUN: lines' >&2
   fail=1
fi

exit "${fail}"
