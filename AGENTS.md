# AGENTS.md (AI-Assisted)

Index for AI tools. Read only the file relevant to your task.

## Before any push (everyone)

Run the static gate (ships in dist-ai as `pre-push-static`). One-shot:

    pre-push-static origin/master

Or install once and forget (dist-ai ships `pre-push-static` on PATH):

    ln -s /usr/bin/pre-push-static .git/hooks/pre-push

It catches R-001 ASCII (commit messages too), `bash -n`,
`shellcheck -x`, Tier-1 single-grep rules from
[`agents/bash-style-guide.md`](agents/bash-style-guide.md), and a
hand-edited genmkfile-owned `debian/changelog` (override with a
`Changelog-manual-ok: <reason>` commit trailer). CI
mirrors the same gate via
[`.github/workflows/reusable-pre-push-static.yml`](.github/workflows/reusable-pre-push-static.yml);
pushing without running it locally just makes CI the slower
feedback loop.

## Per-task index

| Task | File |
| --- | --- |
| Writing bash | [`agents/bash-style-guide.md`](agents/bash-style-guide.md) |
| Pre-push items the gate doesn't catch (manual review) | [`agents/pre-push-checklist.md`](agents/pre-push-checklist.md) |
| GitHub Actions / reusable workflows | [`agents/github-actions.md`](agents/github-actions.md) |
| Consumer-template propagation + per-repo overlays | [`agents/github-actions-consumer-templates.md`](agents/github-actions-consumer-templates.md) |
| Threat model + trust boundaries | [`agents/security.md`](agents/security.md) |

## developer-meta-files only

| Task | File |
| --- | --- |
| github-org-* / dm-github-* tools | [`agents/github-org-tools.md`](agents/github-org-tools.md) |
| Canonical-vs-mirror policy split | [`agents/github-policy-canonical-vs-mirror.md`](agents/github-policy-canonical-vs-mirror.md) |

Other repos (derivative-maker, helper-scripts, etc.) cross-link
here rather than duplicating.

## Tests

Comprehensive tests for two developer-meta-files tools are too high-volume for
human review and live in the AI-maintained dist-ai repo, not here
(https://github.com/org-ai-assisted/dist-ai). Run each against this checkout by
passing the tool path:

    git-meld-tests "$PWD/usr/bin/git-meld"   # usr/share/git-meld-tests/
    dm-virtualbox-wiki-links-tests "$PWD/usr/bin/dm-virtualbox-update-local-and-wiki-links"   # usr/share/dm-virtualbox-wiki-links-tests/
