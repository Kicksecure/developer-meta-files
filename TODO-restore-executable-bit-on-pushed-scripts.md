# TODO: restore executable bit on scripts pushed via the GitHub MCP API

## Problem

The GitHub MCP push tools (`mcp__github__push_files`,
`mcp__github__create_or_update_file`) use the GitHub Contents API
underneath, which constructs new tree entries with mode `100644` even
when the existing tree entry was `100755`. Every file pushed during
the AI-assisted refactor session that was previously executable lost
its executable bit. Codex flagged P1 instances on:

- `tb-updater/usr/libexec/tb-updater/dispvm` - DispVM systemd unit
  `ExecStart=/usr/libexec/tb-updater/dispvm` will fail with
  `Permission denied` / status 203 (EXEC) at exec time.
- `usability-misc/usr/share/usability-misc/build-dist-installer-cli` -
  `usr/share/usability-misc/check-dist-installer-cli:23` invokes it
  directly; that call now fails with `Permission denied` (exit 126).
- `helper-scripts/usr/libexec/helper-scripts/extract-openpgp-policy-trusted-certs` -
  Python entrypoint with shebang; cannot be invoked bare-name after
  packaging install.
- `developer-meta-files/usr/bin/github-org-clone`,
  `usr/bin/github-org-fork`, `usr/bin/github-org-push`,
  `usr/bin/dm-github-policy`, `usr/bin/dm-github-personal-policy`,
  and presumably every other `usr/bin/dm-*` and
  `usr/bin/github-org-*` operator entrypoint.

Confirmed downstream effect on the developer-meta-files mock-API
test suite: 6 of 10 tests fail with rc=126 ("Permission denied")
or the explicit error
`/usr/bin/dm-github-personal-policy: Permission denied`
(see the failing-step log of run 25428163475).

This affects the `claude/read-agents-meta-file-uKeT9` branch in
every repo the AI-assisted session pushed to.

## Why this is not auto-fixed

The MCP write tools available to the AI agent do not expose the Git
Trees API and have no `mode` parameter. There is no in-session way
to set tree entry mode to `100755`. Even with a Contents-write PAT
in the agent's env, the org PAT for `assisted-by-ai` does not have
write scope on org-ai-assisted/* via the git CLI path. The fix has
to come from a maintainer running `git update-index --chmod=+x`
locally and pushing.

## Fix script (run once locally, per affected repo)

```bash
#!/bin/bash
set -euo pipefail
br=claude/read-agents-meta-file-uKeT9
cd <repo>
git fetch origin "$br":"$br"
git checkout "$br"
git ls-files | while read -r f; do
  # only flip if file looks executable (shebang) and current mode in index is 644
  if test -f "$f" && head -c 2 "$f" 2>/dev/null | grep -q '^#!' && \
     test "$(git ls-files -s -- "$f" | awk '{print $1}')" = '100644'; then
    printf '  fix: %s\n' "$f"
    git update-index --chmod=+x -- "$f"
  fi
done
git diff --cached --stat
git commit -m "ci: restore executable bit on shebanged scripts (lost via MCP push)"
git push origin "$br"
```

Run in each of: derivative-maker, helper-scripts, developer-meta-files,
kloak, msgcollector, tb-updater, usability-misc, whonix-firewall,
whonix-starter.

## Once fixed

Codex's P1 review threads on `kloak#1`, `usability-misc#1`,
`tb-updater#1`, `developer-meta-files#1`, and `helper-scripts#1`
will resolve. The 6 mock-API test failures on
developer-meta-files#1 will pass.
