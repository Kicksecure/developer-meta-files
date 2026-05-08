<!--
Copyright (C) 2026 - 2026 ENCRYPTED SUPPORT LLC <adrelanos@whonix.org>
See the file COPYING for copying conditions.

AI-Assisted
-->

# OpenSSF Scorecard - known false positives in this org

When [Scorecard](https://github.com/ossf/scorecard) runs against
the org's repos it produces a number of low scores for things
that are intentional architectural choices or known limits of
Scorecard's heuristics. The list below documents those so
reviewers do not chase ghost issues, and so the genuine signals
in the Scorecard output stand out by contrast.

## DependencyUpdateToolID = 0/10 on consumer repos

**Affects**: `kloak`, `security-misc`, and any future repo that
goes through the reusable-workflow migration.

**Why Scorecard reports it**: it does not see a
`.github/dependabot.yml` in the repo and concludes there is no
dependency update mechanism.

**Why it is intentional**: after the centralization in
[github-actions.md](../agents/github-actions.md), action SHAs
in consumer wrappers are `uses: org-ai-assisted/developer-meta-
files/.github/workflows/X.yml@master` references. The actual
SHA-pinned `actions/checkout`, `anthropics/claude-code-action`,
etc. live in the reusable workflows in this repo. One
`developer-meta-files/.github/dependabot.yml` updates them all;
consumer repos pick up the bumped SHAs automatically through
`@master` on their next workflow run. Adding per-consumer
`dependabot.yml` files would just produce empty PR streams since
the consumers carry no SHAs of their own.

**Detection logic gap**: Scorecard cannot model "this repo
depends on another repo's reusable workflow with `@master`
tracking", so the cross-repo dependency-update path is invisible
to it.

## PinnedDependenciesID firing on `@master` reusable refs

**Affects**: every consumer wrapper (kloak, helper-scripts,
security-misc, derivative-maker) for each `uses:
org-ai-assisted/developer-meta-files/.github/workflows/X.yml
@master` line.

**Why Scorecard reports it**: the `@master` ref is not a SHA pin.
Scorecard treats this the same as a `uses:
foo/bar@<unpinned-tag>` line on a third-party Marketplace
action.

**Why it is intentional**: per
[`agents/github-actions.md`](../agents/github-actions.md)
**G-A-004**, the org has explicitly chosen `@master` over `@<sha>`
for cross-repo reusable workflow refs. The trade-off is
deliberate:

- `@master` -> single-source-of-truth update propagation. Bump a
  reusable's action SHA once in this repo, every consumer's next
  workflow run uses the new SHA. No cross-repo Dependabot dance.
- `@<sha>` -> stronger supply-chain stability per consumer at the
  cost of a per-consumer bump PR every time a reusable changes.

Scorecard cannot distinguish "third-party Marketplace action" from
"intra-org reusable workflow under our own administrative control"
- both render as the same `uses:` syntax. The trust-boundary
argument that motivates SHA pinning for third-party actions does
not apply to a reusable in our own org.

## MaintainedID = 0/10 on freshly-created repos

**Affects**: any repo created within the last 90 days. As of
2026-05-08 this includes the recently-AI-assisted forks under
`org-ai-assisted/`.

**Why Scorecard reports it**: the rule penalizes new repos because
"maintained" is hard to assess from a 5-day commit history.

**Why it is intentional**: nothing to fix. Score auto-resolves to
10/10 once the repo passes the 90-day threshold AND has commits
within the last 90 days. No-op TODO.

## SASTID below 10/10 right after CodeQL adoption

**Affects**: each repo for the first ~30 days after CodeQL was
turned on.

**Why Scorecard reports a partial score**: it counts how many of
the recent default-branch commits have a CodeQL run associated
with them. Commits made before CodeQL was wired up are counted
as "no SAST coverage", lowering the score until the historical
window rolls forward.

**Why it is intentional**: CodeQL is configured on every push to
master + every pull_request to master in the consumer wrappers.
There are no `paths:` filters; every relevant commit is scanned
post-adoption. Score will trend upward naturally.

**What we deliberately did NOT do**: drop the `branches: [master]`
filter on the trigger, so that pushes to dev / feature branches
also fire CodeQL. That would push SASTID toward 10/10 faster but
roughly multiplies CI minute consumption. Per cost-vs-coverage
trade-off, master + PR is the chosen balance.

## Dockerfile `FROM <previous-stage>` flagged as unpinned

**Affects**: `derivative-maker/docker/Dockerfile:17` (`FROM
baseimage`).

**Why Scorecard reports it**: the rule reads `FROM <name>` and
expects a registry digest pin (`@sha256:...`).

**Why it is a false positive**: `baseimage` is a local multi-stage
build target defined earlier in the same Dockerfile (`FROM
debian:trixie-slim@sha256:... AS baseimage` on line 4). It does
not pull from a registry; the upstream digest is already pinned
on the AS-line and does not need to be repeated. Scorecard's
heuristic does not parse multi-stage builds.

**No fix on the Scorecard side**: dismiss the alert, or wait for
upstream Scorecard to learn multi-stage Dockerfiles.

## What we DO act on

The Scorecard signals NOT in this list are real and worth fixing.
Notable currently-actionable categories:

- **SecurityPolicyID**: add a `SECURITY.md` (likely centralized in
  `org-ai-assisted/.github` for org-wide default).
- **BranchProtectionID**: enable branch protection on `master` in
  GitHub repo Settings -> Branches.
- **CodeReviewID**: enforce "require approvals" via branch
  protection so the PR-approval rate climbs from the current ~0%.
- **FuzzingID**: add fuzzing harnesses where the language
  ecosystem supports it (helper-scripts already runs Hypothesis +
  Atheris; kloak / security-misc are open work).
- **`pipCommand` / `containerImage` PinnedDependenciesID**: real -
  pin pip installs by hash, or replace with apt-installed Debian
  packages where available. derivative-maker handled in commit
  history; reapply the same approach to any new pip/Dockerfile
  surface.
