<!--
Copyright (C) 2026 - 2026 ENCRYPTED SUPPORT LLC <adrelanos@whonix.org>
See the file COPYING for copying conditions.
-->

# OpenSSF Scorecard - known false positives in this org (AI-Assisted)

When [Scorecard](https://github.com/ossf/scorecard) runs against
the org's repos it produces a number of low scores for things
that are intentional architectural choices or known limits of
Scorecard's heuristics. The list below documents those so
reviewers do not chase ghost issues, and so the genuine signals
in the Scorecard output stand out by contrast.

## DependencyUpdateToolID = 0/10 on consumer repos

**Affects**: `kloak`, `security-misc`, and any future repo that
goes through the reusable-workflow migration. Also every
shell-only / config-only repo in the org (`whonix-firewall`,
`Whonix-Installer`, `usability-misc`, `tb-updater`, `genmkfile`,
`Whonix-Starter`, `msgcollector`) - none of those have a
language-level dependency manifest Dependabot or Renovate even
supports.

**Why Scorecard reports it**: the check looks at **file presence
only** (verified against the source at
[`checks/raw/dependency_update_tool.go`](https://github.com/ossf/scorecard/blob/main/checks/raw/dependency_update_tool.go))
- `.github/dependabot.yml`, `.github/dependabot.yaml`, Renovate
configs, scala-steward configs. Org-level Dependabot enablement
is invisible to it.

**Why it is intentional**:

For consumer-wrapper repos: after the centralization in
[github-actions.md](../agents/github-actions.md), action SHAs
in consumer wrappers are `uses: org-ai-assisted/developer-meta-
files/.github/workflows/reusable-<name>.yml@master` references.
The actual SHA-pinned `actions/checkout`,
`anthropics/claude-code-action`, etc. live in the reusable
workflows in this repo. One
`developer-meta-files/.github/dependabot.yml` updates them all;
consumer repos pick up the bumped SHAs automatically through
`@master` on their next workflow run. Adding per-consumer
`dependabot.yml` files would just produce empty PR streams since
the consumers carry no SHAs of their own.

For shell-only / config-only repos: there is genuinely nothing
for a dependency-update tool to bump - no `package.json`,
`requirements.txt`, `go.mod`, `Gemfile`, etc. The check has no
way to express "N/A" so it reports 0/10.

**Detection logic gap**: Scorecard cannot model (a) "this repo
depends on another repo's reusable workflow with `@master`
tracking", nor (b) "this repo has no language-level
dependencies to update". Both are well-known upstream:

- [ossf/scorecard#1903](https://github.com/ossf/scorecard/issues/1903)
  - org-level Dependabot enablement should count as evidence
  (open). Confirms the file-presence-only model.
- [ossf/scorecard#2190](https://github.com/ossf/scorecard/issues/2190)
  - don't penalize repos with no dependencies at all (open;
  closest direct match for our shell-only repos).
- [ossf/scorecard#3746](https://github.com/ossf/scorecard/issues/3746)
  - return inconclusive (-1) score for repos with no relevant
  deps (open; on the active "Policy per Ecosystem" milestone -
  most likely vehicle for a fix).
- [ossf/scorecard#1726](https://github.com/ossf/scorecard/issues/1726)
  - check should detect ecosystems with no Dependabot / Renovate
  support (e.g., C / C++) and not score 0/10 (open).
- [ossf/scorecard#2483](https://github.com/ossf/scorecard/issues/2483)
  - cURL-driven feedback that C projects without a widely-
  adopted dep manager shouldn't be penalized (open, stale).
- [ossf/scorecard#1014](https://github.com/ossf/scorecard/issues/1014)
  - libraries-vs-applications framing of the check (open;
  tangential).
- [ossf/scorecard#4795](https://github.com/ossf/scorecard/issues/4795)
  - "filter out incompatible repository checks" (closed
  Sept 2025, completed); broader infrastructure that would
  unblock the per-check fixes above.

**What to do about it**: nothing on our side. Adding empty
`dependabot.yml` files to satisfy the check would be pure
compliance theatre - they would open zero PRs in practice
because there is nothing for them to bump. A `+1` comment on
**#3746** with our shell-only repos as concrete examples is
more useful than yet another duplicate issue.

## PinnedDependenciesID firing on `@master` reusable refs

**Affects**: every consumer wrapper (kloak, helper-scripts,
security-misc, derivative-maker) for each `uses:
org-ai-assisted/developer-meta-files/.github/workflows/reusable-
<name>.yml@master` line.

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

## Signed-Releases = inconclusive (and that is the goal)

**Affects**: every repo in `org-ai-assisted`, `Kicksecure`,
`Whonix`, and `adrelanos`.

**Current state**: none of these repos has ever had a GitHub
Release object created. Tags exist (signed, ruleset-enforced) but
no Releases. Scorecard's `Signed-Releases` returns `-1`
(inconclusive) per `checks/evaluation/signed_releases.go` and is
excluded from the aggregate score.

**Why it is intentional**: published artifacts (ISOs, .debs) ship
via the project's signed apt repo and download server, NOT via
GitHub releases. The maintainer's signing key is offline by
design and never touches a GitHub runner or any remote server.
Adding GitHub Release objects with only the auto-generated
source archives would flip Scorecard from inconclusive to **0/10**
(real penalty: source-only releases are NOT skipped, they count
as unsigned). A 10/10 path would require either putting the key
on a runner (forbidden) or adopting Sigstore/SLSA-on-Actions
(wrong tool — GitHub Actions is deliberately not in the
artifact path).

**What to do**: nothing. Do NOT create GitHub Release objects on
these repos. The current state is the desired state.

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
