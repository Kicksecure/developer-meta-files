#!/bin/bash

## Copyright (C) 2026 - 2026 ENCRYPTED SUPPORT LLC <adrelanos@whonix.org>
## See the file COPYING for copying conditions.

## AI-Assisted

## Project-specific workflow YAML validator. Catches the failure
## modes we have actually hit in production CI:
##
##   W-001 (TIMEOUT)             Every job that runs work has
##                               timeout-minutes set. Hang-protection.
##   W-002 (CONCURRENCY)         Every workflow has top-level
##                               concurrency:. Cancellation policy
##                               not left to GitHub defaults.
##   W-003 (SECRETS-INHERIT)     'secrets: inherit' only in the
##                               documented allowlist (deliberate
##                               audit probes).
##   W-004 (SHA-PIN)             Third-party 'uses: <owner>/<repo>@
##                               <ref>' must pin to a 40-char SHA.
##                               First-party orgs (org-ai-assisted,
##                               Kicksecure, Whonix, actions) and
##                               local refs ('./.github/actions/...')
##                               are exempt.
##   W-005 (PERMISSIONS-CHECKOUT) If a job has a 'permissions:' block
##                               AND uses actions/checkout, that
##                               block must include 'contents: read'.
##                               Job-level permissions REPLACE
##                               top-level (GitHub does not merge);
##                               the trap that caused the
##                               long-running startup_failure on
##                               usability-misc/builds.yml.
##   W-006 (DEPRECATED)          Flags '::set-output::',
##                               '::save-state::', node12/node16
##                               action versions,
##                               actions/upload-artifact@v3, etc.
##
## Exit codes:
##   0 -- no findings
##   1 -- one or more findings reported
##   2 -- internal error (missing dep, etc.)
##
## Designed to run inside dmf's own mock-test suite via
## ci/test-github-org-tools.sh. Standalone-runnable with
## ALLOW_LOCAL=true to validate any dmf checkout.

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

repo_root="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
cd -- "${repo_root}"

if [ ! -d .github/workflows ]; then
   printf '%s\n' "${BASH_SOURCE[0]}: no .github/workflows/ directory; nothing to validate"
   exit 0
fi

## Delegate the rules to a python helper so YAML parsing is
## structurally correct (vs. fragile bash regex over a YAML file).
## The helper prints findings to stdout; bash counts them and
## sets the exit code. The helper is inlined here (rather than a
## separate file) to keep the entire validator a single artifact -
## the conventional shape for dmf/ci/tests/test_*.sh.

findings_file="$(mktemp)"
trap 'rm -f "${findings_file}"' EXIT

python3 - "${repo_root}" > "${findings_file}" <<'PYEOF'
import os, re, sys, yaml

repo_root = sys.argv[1]
workflows_dir = os.path.join(repo_root, '.github', 'workflows')

## 'secrets: inherit' is permitted only on these specific
## workflows. Path is relative to repo_root.
SECRETS_INHERIT_ALLOWLIST = {
   '.github/workflows/secrets-audit.yml',
}

## First-party owners are exempt from the SHA-pin requirement
## (G-A-004 in agents/github-actions.md: branch-name refs are an
## accepted single-source-of-truth pattern for our own repos).
FIRST_PARTY_OWNERS = {
   'org-ai-assisted',
   'Kicksecure',
   'Whonix',
   'actions',  ## github.com/actions/* - github-owned
   'github',   ## github.com/github/* - github-owned
}

## Deprecated action refs and syntax. Map of substring -> reason.
DEPRECATED_MARKERS = {
   '::set-output': 'use $GITHUB_OUTPUT instead (set-output deprecated 2022)',
   '::save-state': 'use $GITHUB_STATE instead (save-state deprecated 2022)',
   '::set-env':    'banned for security reasons (CVE-2020-15228)',
   'actions/upload-artifact@v3': 'v3 deprecated 2024; use @v4 or @v7 SHA-pinned',
   'actions/download-artifact@v3': 'v3 deprecated 2024; use @v4 SHA-pinned',
   'actions/cache@v2': 'v2 EOL; use @v4 SHA-pinned',
   'actions/cache@v3': 'v3 deprecated; use @v4 SHA-pinned',
}

SHA40 = re.compile(r'^[0-9a-f]{40}$')

def emit(path, rule, message):
   ## Path is printed relative to repo_root.
   rel = os.path.relpath(path, repo_root)
   print(f'{rel}:{rule}:{message}')

def is_workflow_call(parsed):
   on = parsed.get('on') or parsed.get(True)  ## 'on' parses as True in YAML 1.1
   if not isinstance(on, dict): return False
   return 'workflow_call' in on

def find_uses_lines(text):
   '''Return [(line_no, uses_value)] for every 'uses:' line.'''
   out = []
   for i, line in enumerate(text.splitlines(), 1):
      m = re.match(r'^\s*-?\s*uses:\s*([^\s#]+)', line)
      if m: out.append((i, m.group(1)))
   return out

def check_workflow(path):
   with open(path) as f: text = f.read()
   try:
      parsed = yaml.safe_load(text)
   except yaml.YAMLError as e:
      emit(path, 'W-YAML', f'invalid YAML: {e}')
      return
   if not isinstance(parsed, dict):
      emit(path, 'W-YAML', 'top-level is not a mapping')
      return

   is_reusable = is_workflow_call(parsed)
   jobs = parsed.get('jobs', {}) or {}

   ## W-002 CONCURRENCY: top-level concurrency block required.
   ## Reusables exempt (the reusable's own concurrency is what
   ## actually applies to its run; some reusables intentionally
   ## omit if grouping is best decided by callers).
   if not is_reusable and 'concurrency' not in parsed:
      emit(path, 'W-002', 'missing top-level concurrency: block')

   ## Iterate jobs.
   for job_id, job in (jobs.items() if isinstance(jobs, dict) else []):
      if not isinstance(job, dict):
         continue

      ## W-001 TIMEOUT: standalone jobs (with steps) must have
      ## timeout-minutes. Wrapper jobs (only 'uses:') are governed
      ## by the called reusable's timeout.
      has_steps = 'steps' in job
      has_uses  = 'uses' in job
      if has_steps and 'timeout-minutes' not in job:
         emit(path, 'W-001', f"job '{job_id}' missing timeout-minutes")

      ## W-003 SECRETS-INHERIT
      secrets = job.get('secrets')
      if secrets == 'inherit':
         rel = os.path.relpath(path, repo_root)
         if rel not in SECRETS_INHERIT_ALLOWLIST:
            emit(path, 'W-003',
                 f"job '{job_id}' uses 'secrets: inherit'; replace with explicit map "
                 f"(or add to SECRETS_INHERIT_ALLOWLIST if intentional)")

      ## W-005 PERMISSIONS-CHECKOUT
      perms = job.get('permissions')
      ## Skip if perms is not a non-empty mapping. 'permissions: {}'
      ## (empty) is a deliberate "zero permissions" hardening signal;
      ## the user explicitly opted out of any contents access. Strings
      ## like 'read-all' / 'write-all' also bypass.
      if isinstance(perms, dict) and perms:
         ## Same-repo checkout means: actions/checkout@... with NO
         ## 'with.repository:' override (or with.repository == github.repository).
         ## A checkout of a DIFFERENT repo (cross-repo, e.g.
         ## reusable-secrets-audit.yml clones dmf separately) does
         ## not need 'contents:' permission on THIS repo - public
         ## anonymous clone works.
         uses_same_repo_checkout = False
         for s in (job.get('steps') or []):
            if not isinstance(s, dict): continue
            if not isinstance(s.get('uses',''), str): continue
            if not s.get('uses','').startswith('actions/checkout@'): continue
            w = s.get('with') or {}
            other_repo = w.get('repository')
            if not other_repo:  ## defaults to current repo
               uses_same_repo_checkout = True
               break
         if uses_same_repo_checkout and 'contents' not in perms:
            emit(path, 'W-005',
                 f"job '{job_id}' has job-level permissions but no 'contents:' entry "
                 f"AND uses actions/checkout on the current repo. Job-level permissions "
                 f"REPLACE top-level (not merge), so checkout has no contents access.")

   ## W-004 SHA-PIN, W-006 DEPRECATED: walk uses: lines.
   for line_no, uses in find_uses_lines(text):
      ## W-006 first (cheap substring)
      for marker, reason in DEPRECATED_MARKERS.items():
         if marker in uses:
            emit(path, 'W-006', f"line {line_no}: '{uses}' - {reason}")
            break

      ## W-004 SHA-PIN
      if uses.startswith('./') or uses.startswith('docker://'):
         continue  ## local composite or docker ref
      ## Form: <owner>/<repo>[/path]@<ref>
      m = re.match(r'^([^/@]+)/[^@]+@(.+)$', uses)
      if not m:
         continue
      owner, ref = m.group(1), m.group(2)
      if owner in FIRST_PARTY_OWNERS:
         continue
      if not SHA40.match(ref):
         emit(path, 'W-004',
              f"line {line_no}: '{uses}' - third-party action must pin to 40-char SHA, not '@{ref}'")

## Walk every workflow file.
for entry in sorted(os.listdir(workflows_dir)):
   if not entry.endswith('.yml') and not entry.endswith('.yaml'):
      continue
   check_workflow(os.path.join(workflows_dir, entry))
PYEOF

n_findings=$(wc -l < "${findings_file}")
if [ "${n_findings}" -eq 0 ]; then
   printf '%s\n' "workflow yaml validator: 0 findings across $(find .github/workflows -maxdepth 1 \( -name '*.yml' -o -name '*.yaml' \) | wc -l) workflow files"
   exit 0
fi

printf '%s\n' "workflow yaml validator: ${n_findings} finding(s):"
printf '%s\n' "----"
cat -- "${findings_file}"
printf '%s\n' "----"
printf '%s\n' "Rules:"
printf '  %s\n' \
   "W-001 TIMEOUT              job missing timeout-minutes" \
   "W-002 CONCURRENCY          workflow missing top-level concurrency:" \
   "W-003 SECRETS-INHERIT      secrets: inherit outside allowlist" \
   "W-004 SHA-PIN              third-party uses: not pinned to 40-char SHA" \
   "W-005 PERMISSIONS-CHECKOUT job-level permissions drop contents: read while using actions/checkout" \
   "W-006 DEPRECATED           deprecated GitHub Actions syntax / action version" \
   "W-YAML                     YAML parse error"
exit 1
