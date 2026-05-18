#!/usr/bin/python3

## Copyright (C) 2026 - 2026 ENCRYPTED SUPPORT LLC <adrelanos@whonix.org>
## See the file COPYING for copying conditions.

## AI-Assisted

"""Project-specific GitHub workflow YAML validator.

Walks .github/workflows/*.yml under the given repo root and applies
six rules:

  W-001 TIMEOUT              Every job that runs work has
                             timeout-minutes set.
  W-002 CONCURRENCY          Every non-reusable workflow has a
                             top-level concurrency: block.
  W-003 SECRETS-INHERIT      'secrets: inherit' only in the
                             documented allowlist.
  W-004 SHA-PIN              Third-party 'uses: <owner>/<repo>@
                             <ref>' must pin to a 40-char SHA AND
                             carry a '# v<tag>' provenance comment.
                             First-party orgs (org-ai-assisted,
                             Kicksecure, Whonix) and local refs are
                             exempt. Note: 'actions/*' (GitHub-
                             owned) is NOT first-party; supply-chain
                             hygiene applies to GitHub's marketplace
                             actions too.
  W-005 PERMISSIONS-CHECKOUT If a job has a non-empty permissions
                             block AND uses actions/checkout on the
                             current repo, that block must include
                             'contents: read'. Job-level permissions
                             REPLACE top-level (GitHub does not
                             merge).
  W-006 DEPRECATED           ::set-output, ::save-state, node12,
                             node16, actions/upload-artifact@v3,
                             etc.
  W-007 DEPENDABOT-MISSING   Repo has direct third-party action SHA
                             pins in its workflows but no
                             .github/dependabot.yml to track bumps.
                             Repos with zero direct refs (pure
                             '@master'-to-dmf-reusable wrappers) are
                             exempt - dmf's single Dependabot config
                             propagates SHA bumps to them.

Usage: python3 test_workflow_yaml.py <repo_root>

Exit codes:
  0  no findings
  1  one or more findings reported
  2  internal error (bad invocation, missing dep)
"""

import os
import re
import sys

try:
    import yaml
except ImportError:
    print('error: PyYAML not installed (apt: python3-yaml)', file=sys.stderr)
    sys.exit(2)


## 'secrets: inherit' is permitted only on these specific
## workflows. Path is relative to repo_root.
SECRETS_INHERIT_ALLOWLIST = {
    '.github/workflows/consumer-secrets-audit.yml',
}

## First-party owners are exempt from SHA-pin (G-A-004 in
## agents/github-actions.md: branch-name refs are an accepted
## single-source-of-truth pattern for our own repos). 'actions' and
## 'github' (GitHub-owned) are NOT in this set: even GitHub's own
## marketplace actions must be SHA-pinned per supply-chain hygiene.
FIRST_PARTY_OWNERS = {
    'org-ai-assisted',
    'Kicksecure',
    'Whonix',
}

## Deprecated action refs and syntax. Map of substring -> reason.
DEPRECATED_MARKERS = {
    '::set-output': 'use $GITHUB_OUTPUT instead (set-output deprecated 2022)',
    '::save-state': 'use $GITHUB_STATE instead (save-state deprecated 2022)',
    '::set-env': 'banned for security reasons (CVE-2020-15228)',
    'actions/upload-artifact@v3': 'v3 deprecated 2024; use @v4 or @v7 SHA-pinned',
    'actions/download-artifact@v3': 'v3 deprecated 2024; use @v4 SHA-pinned',
    'actions/cache@v2': 'v2 EOL; use @v4 SHA-pinned',
    'actions/cache@v3': 'v3 deprecated; use @v4 SHA-pinned',
}

SHA40 = re.compile(r'^[0-9a-f]{40}$')

RULE_LEGEND = [
    ('W-001 TIMEOUT',              'job missing timeout-minutes'),
    ('W-002 CONCURRENCY',          'workflow missing top-level concurrency:'),
    ('W-003 SECRETS-INHERIT',      'secrets: inherit outside allowlist'),
    ('W-004 SHA-PIN',              'third-party uses: not pinned to 40-char SHA'),
    ('W-005 PERMISSIONS-CHECKOUT', 'job-level permissions drop contents: read while using actions/checkout'),
    ('W-006 DEPRECATED',           'deprecated GitHub Actions syntax / action version'),
    ('W-007 DEPENDABOT-MISSING',   'direct third-party SHAs but no .github/dependabot.yml'),
    ('W-YAML',                     'YAML parse error'),
]


def emit(findings, path, repo_root, rule, message):
    rel = os.path.relpath(path, repo_root)
    findings.append(f'{rel}:{rule}:{message}')


def is_workflow_call(parsed):
    on = parsed.get('on')
    if on is None:
        ## 'on' parses as Python True under YAML 1.1.
        on = parsed.get(True)
    if not isinstance(on, dict):
        return False
    return 'workflow_call' in on


def is_composite_action(parsed):
    runs = parsed.get('runs')
    if not isinstance(runs, dict):
        return False
    return runs.get('using') == 'composite'


def find_uses_lines(text):
    """Return [(line_no, uses_value, tag_comment)] for every 'uses:' line.

    tag_comment is the inline comment text after '#' on the same
    line (None if no inline comment present).
    """
    out = []
    for i, line in enumerate(text.splitlines(), 1):
        m = re.match(r'^\s*-?\s*uses:\s*([^\s#]+)(\s*#\s*(.+))?', line)
        if m:
            tag = m.group(3).strip() if m.group(3) else None
            out.append((i, m.group(1), tag))
    return out


def check_workflow(path, repo_root, findings):
    with open(path) as f:
        text = f.read()
    try:
        parsed = yaml.safe_load(text)
    except yaml.YAMLError as e:
        emit(findings, path, repo_root, 'W-YAML', f'invalid YAML: {e}')
        return
    if not isinstance(parsed, dict):
        emit(findings, path, repo_root, 'W-YAML', 'top-level is not a mapping')
        return

    ## Composite action files (.github/actions/*/action.yml) only
    ## have W-004 / W-006 applicable - no jobs:, no concurrency:,
    ## no secrets. Skip workflow-only rules for them but still walk
    ## uses: lines below.
    if not is_composite_action(parsed):
        is_reusable = is_workflow_call(parsed)
        jobs = parsed.get('jobs') or {}

        ## W-002 CONCURRENCY (reusables exempt)
        if not is_reusable and 'concurrency' not in parsed:
            emit(findings, path, repo_root, 'W-002', 'missing top-level concurrency: block')

        if isinstance(jobs, dict):
            for job_id, job in jobs.items():
                if not isinstance(job, dict):
                    continue
                check_job(path, repo_root, findings, job_id, job)

    ## W-004 SHA-PIN, W-006 DEPRECATED: walk uses: lines.
    for line_no, uses, tag_comment in find_uses_lines(text):
        for marker, reason in DEPRECATED_MARKERS.items():
            if marker in uses:
                emit(findings, path, repo_root, 'W-006',
                     f"line {line_no}: '{uses}' - {reason}")
                break

        if uses.startswith('./') or uses.startswith('docker://'):
            continue  ## local composite or docker ref
        m = re.match(r'^([^/@]+)/[^@]+@(.+)$', uses)
        if not m:
            continue
        owner = m.group(1)
        ref = m.group(2)
        if owner in FIRST_PARTY_OWNERS:
            continue
        if not SHA40.match(ref):
            emit(findings, path, repo_root, 'W-004',
                 f"line {line_no}: '{uses}' - third-party action must pin to 40-char SHA, not '@{ref}'")
            continue
        ## SHA pinned. Now require a '# v<digit>...' provenance comment.
        if not tag_comment or not re.match(r'^v?\d', tag_comment):
            emit(findings, path, repo_root, 'W-004',
                 f"line {line_no}: '{uses}' - SHA pinned but missing '# v<tag>' provenance comment "
                 f'(found: {tag_comment!r})')


def check_job(path, repo_root, findings, job_id, job):
    ## W-001 TIMEOUT: standalone jobs (with steps) must have
    ## timeout-minutes. Wrapper jobs (only 'uses:') are governed
    ## by the called reusable's timeout.
    if 'steps' in job and 'timeout-minutes' not in job:
        emit(findings, path, repo_root, 'W-001',
             f"job '{job_id}' missing timeout-minutes")

    ## W-003 SECRETS-INHERIT
    if job.get('secrets') == 'inherit':
        rel = os.path.relpath(path, repo_root)
        if rel not in SECRETS_INHERIT_ALLOWLIST:
            emit(findings, path, repo_root, 'W-003',
                 f"job '{job_id}' uses 'secrets: inherit'; replace with explicit map "
                 f'(or add to SECRETS_INHERIT_ALLOWLIST if intentional)')

    ## W-005 PERMISSIONS-CHECKOUT
    perms = job.get('permissions')
    ## Skip if perms is not a non-empty mapping. 'permissions: {}'
    ## (empty) is a deliberate "zero permissions" hardening signal;
    ## strings like 'read-all' / 'write-all' also bypass.
    if not (isinstance(perms, dict) and perms):
        return
    ## Same-repo checkout means: actions/checkout@... with NO
    ## 'with.repository:' override. Cross-repo public-anonymous
    ## clone does not need 'contents:' permission on THIS repo.
    uses_same_repo_checkout = False
    for s in (job.get('steps') or []):
        if not isinstance(s, dict):
            continue
        s_uses = s.get('uses', '')
        if not isinstance(s_uses, str):
            continue
        if not s_uses.startswith('actions/checkout@'):
            continue
        w = s.get('with') or {}
        if not w.get('repository'):
            uses_same_repo_checkout = True
            break
    if uses_same_repo_checkout and 'contents' not in perms:
        emit(findings, path, repo_root, 'W-005',
             f"job '{job_id}' has job-level permissions but no 'contents:' entry "
             f'AND uses actions/checkout on the current repo. Job-level permissions '
             f'REPLACE top-level (not merge), so checkout has no contents access.')


def collect_target_files(repo_root):
    """Workflows + composite-action definitions."""
    targets = []
    workflows_dir = os.path.join(repo_root, '.github', 'workflows')
    if os.path.isdir(workflows_dir):
        for entry in sorted(os.listdir(workflows_dir)):
            if entry.endswith('.yml') or entry.endswith('.yaml'):
                targets.append(os.path.join(workflows_dir, entry))
    actions_dir = os.path.join(repo_root, '.github', 'actions')
    if os.path.isdir(actions_dir):
        for action_name in sorted(os.listdir(actions_dir)):
            for filename in ('action.yml', 'action.yaml'):
                p = os.path.join(actions_dir, action_name, filename)
                if os.path.isfile(p):
                    targets.append(p)
    return targets


def check_dependabot(repo_root, targets, findings):
    """W-007: if the repo has any direct third-party 'uses:' (non-
    first-party, non-local), it must have .github/dependabot.yml.
    Pure '@master'-to-dmf-reusable wrappers (zero direct refs)
    are exempt - dmf's single Dependabot covers them.
    """
    dependabot_path = os.path.join(repo_root, '.github', 'dependabot.yml')
    if os.path.isfile(dependabot_path):
        return
    if os.path.isfile(os.path.join(repo_root, '.github', 'dependabot.yaml')):
        return

    has_direct = False
    for t in targets:
        with open(t) as f:
            for _, uses, _ in find_uses_lines(f.read()):
                if uses.startswith('./') or uses.startswith('docker://'):
                    continue
                m = re.match(r'^([^/@]+)/[^@]+@(.+)$', uses)
                if not m:
                    continue
                if m.group(1) not in FIRST_PARTY_OWNERS:
                    has_direct = True
                    break
        if has_direct:
            break

    if has_direct:
        findings.append(
            f'.github/dependabot.yml:W-007:repo has direct third-party action SHA pins '
            f"but no .github/dependabot.yml; SHA bumps won't be tracked"
        )


def main(repo_root):
    targets = collect_target_files(repo_root)
    if not targets:
        print(f'workflow yaml validator: no workflow / composite-action files; nothing to validate')
        return 0

    findings = []
    for p in targets:
        check_workflow(p, repo_root, findings)
    check_dependabot(repo_root, targets, findings)
    n_files = len(targets)

    if not findings:
        print(f'workflow yaml validator: 0 findings across {n_files} files')
        return 0

    print(f'workflow yaml validator: {len(findings)} finding(s):')
    print('----')
    for f in findings:
        print(f)
    print('----')
    print('Rules:')
    for rule, desc in RULE_LEGEND:
        print(f'  {rule:<27} {desc}')
    return 1


if __name__ == '__main__':
    if len(sys.argv) != 2:
        print('usage: test_workflow_yaml.py <repo_root>', file=sys.stderr)
        sys.exit(2)
    sys.exit(main(sys.argv[1]))
