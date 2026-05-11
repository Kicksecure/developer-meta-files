# AGENTS.md (AI-Assisted)

* Index of guidance for AI tools (Claude Code, Codex, etc.).
* Read only the file relevant to your task.
* `AGENTS.md` itself stays short on purpose.

# AI instructions for ALL repositories

**Before pushing, run [`agents/pre-push-static.sh`](agents/pre-push-static.sh)
(or install it once as `.git/hooks/pre-push`).** It enforces
R-001 ASCII (commit messages too), `bash -n`, `shellcheck -x`,
and Tier-1 grep rules from the bash style guide. CI mirrors the
same gate via
[`reusable-pre-push-static.yml`](.github/workflows/reusable-pre-push-static.yml),
so PRs that ignore the local hook still get blocked at merge.

| Topic | Where |
| --- | --- |
| Bash style (variables, printf, locals, traps, ...) | [`agents/bash-style-guide.md`](agents/bash-style-guide.md) |
| pre-push checklist (skim before push) | [`agents/pre-push-checklist.md`](agents/pre-push-checklist.md) |
| pre-push static gate (run before push; enforces R-001 ASCII, `bash -n`, `shellcheck -x`) | [`agents/pre-push-static.sh`](agents/pre-push-static.sh) |
| GitHub Actions cross-repo conventions (reusable workflows, context constraints) | [`agents/github-actions.md`](agents/github-actions.md) |
| General threat model + trust boundaries | [`agents/security.md`](agents/security.md) |

Other repos (derivative-maker, helper-scripts, etc.) cross-link here
rather than duplicating.

# AI instructions for developer-meta-files repository only

| Topic | Where |
| --- | --- |
| github-org-* / dm-github-* specifics | [`agents/github-org-tools.md`](agents/github-org-tools.md) |
| Canonical-vs-mirror policy split (SOURCE / MIRROR / PERSON / BOT diffs) | [`agents/github-policy-canonical-vs-mirror.md`](agents/github-policy-canonical-vs-mirror.md) |
