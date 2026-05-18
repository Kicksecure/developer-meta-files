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

**Upstream tracking**:

- [ossf/scorecard#4735](https://github.com/ossf/scorecard/issues/4735)
  - Apache Maven's identical scenario (open, stale). Consumers
  of `apache/maven-gh-actions-shared` flagged even though the
  shared repo is itself pinned. The active issue to follow / +1.
- [ossf/scorecard#2174](https://github.com/ossf/scorecard/issues/2174)
  - history: Scorecard originally did NOT flag reusable
  workflows; #2174 asked for them to be treated like Marketplace
  actions. Closed completed Jun 2025 - that change is what
  produced the current false positive we live with.
- [slsa-framework/slsa-github-generator#722](https://github.com/slsa-framework/slsa-github-generator/issues/722)
  - the contention: SLSA generators argue reusables MUST be
  pinned by TAG (not SHA) for generator-self-security reasons -
  direct conflict with Scorecard's "SHA only" expectation.
- [ossf/scorecard#2518](https://github.com/ossf/scorecard/issues/2518)
  - tangential: dev-only-deps false positive, same trust-boundary
  class.

Source-inferred: `checks/raw/pinned_dependencies.go` contains no
mention of "reusable"; Scorecard treats every `uses:` uniformly,
no same-org exemption. (Verified via repo-wide code search.)

## MaintainedID = 0/10 on freshly-created repos

**Affects**: any repo created within the last 90 days. As of
2026-05-08 this includes the recently created AI-assisted forks under
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

## Signed-Releases = inconclusive (and that is the goal)

**Affects**: every repo in `Kicksecure` and `Whonix`.

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
(wrong tool - GitHub Actions is deliberately not in the
artifact path).

**What to do**: nothing. Do NOT create GitHub Release objects on
these repos. The current state is the desired state.

**Upstream docs status**:

- [docs/checks.md Signed-Releases](https://github.com/ossf/scorecard/blob/main/docs/checks.md#signed-releases)
  - the only spec. Does NOT document the inconclusive-on-zero-
  releases behavior, does NOT acknowledge external release
  channels (apt, custom download servers).

**Source caveat - inconclusive is undocumented + treated as a
test-fixture path**: the inconclusive branch in
`checks/evaluation/signed_releases.go` carries a maintainer
comment: "This should not happen in production, but it is
useful to have for testing." A future Scorecard change could
flip projects-with-no-releases from inconclusive to 0/10
without breaking any documented contract. Watch the issues
below.

**Upstream tracking**:

- [ossf/scorecard#3679](https://github.com/ossf/scorecard/issues/3679)
  - **most relevant**: "Improve signed releases checks" - asks
  Scorecard to handle projects that don't use GitHub Releases
  or GitHub Actions; proposes checking signed git tags and
  detecting packaging on external repos. The active issue to
  follow / +1 for our scenario.
- [ossf/scorecard#4528](https://github.com/ossf/scorecard/issues/4528)
  - Maven Central as the release channel, GitHub Releases
  empty. Same trust-boundary class as ours.
- [ossf/scorecard#4713](https://github.com/ossf/scorecard/issues/4713)
  - "Signed Releases documentation unhelpful" - PyPI trusted
  publishing case; doc should acknowledge non-GitHub channels.
- [ossf/scorecard#4823](https://github.com/ossf/scorecard/issues/4823)
  - "Pass Signed-Releases with GitHub immutable release
  process" - alternative to SLSA, related PR #5002.
- [ossf/scorecard#2763](https://github.com/ossf/scorecard/issues/2763)
  - confirms the `?` symbol on the Scorecard report represents
  the inconclusive outcome (vs `0/10` penalty).
- [ossf/scorecard#382](https://github.com/ossf/scorecard/issues/382)
  - long-standing ask: actually verify signatures (vs filename
  match). Tangential but relevant context: the current check is
  filename-pattern only.

No upstream issue analogous to #1903 (the org-level Dependabot
trust-boundary recognition) yet exists for Signed-Releases -
#3679 is the closest "this isn't how every project releases"
ask but has no resolution.


## actions/untrusted-checkout/medium (CodeQL Actions) on dmf-checkout steps

**Affects**: every reusable workflow that checks
`developer-meta-files` into `.github/dmf/` for downstream
`ci/`-helper scripts -
[`reusable-pre-push-static.yml`](../.github/workflows/reusable-pre-push-static.yml),
[`reusable-bandit.yml`](../.github/workflows/reusable-bandit.yml),
[`reusable-cppcheck.yml`](../.github/workflows/reusable-cppcheck.yml),
[`reusable-codeql.yml`](../.github/workflows/reusable-codeql.yml),
[`reusable-secrets-audit.yml`](../.github/workflows/reusable-secrets-audit.yml),
[`reusable-scorecard.yml`](../.github/workflows/reusable-scorecard.yml).

**Why CodeQL reports it**: the rule fires on static properties
("this job has write permissions AND it checks out cross-repo
code") and ignores runtime guards - job-level `if:`, step-level
`if:`, `persist-credentials: false` - none of them change the
rule's evaluation. Empirically confirmed twice: alert #17 closed
when step-level `if:` was added by the CodeQL autofix; #82
opened at the same line on the next scan. PR #95 then added the
same guard pattern to #18/#19/#66/#69/#70; the same scan flipped
all six to "fixed" and opened #82-#87 at identical lines. The
rule has no configuration to disable for a specific actor-trust
posture, so the alerts regenerate on every scan.

**Why it is intentional**: per
[`agents/security.md`](../agents/security.md) Threat-model-A,
`github.com` is the trust root for CI workflows in this org.
Real mitigations (already in place):

- Job-level `if: github.event.pull_request.head.repo.full_name == github.repository || github.event_name != 'pull_request'`
  blocks fork PRs from running the job at all. Same-repo PRs are
  by definition org-member-authored and trusted under the model.
- `persist-credentials: false` on every checkout (no token left
  in the working tree).
- No `pull_request_target` triggers anywhere in the org.
- Cached payloads are apt `.deb`s re-verified by `apt-get install`
  against fresh `Packages` metadata, per agents/github-actions.md
  G-A-007.

The codebase deliberately does not redesign these into a
`pull_request` + `workflow_run` split (the rule's documented
"clean" answer) - the trust model does not require the split,
and the redesign would push real work onto every reusable for a
purely cosmetic CodeQL improvement.

## actions/unpinned-tag (CodeQL Actions) on first-party `@master` refs

**Affects**:
[`reusable-bandit.yml:109`](../.github/workflows/reusable-bandit.yml),
[`reusable-coverity.yml:205`](../.github/workflows/reusable-coverity.yml),
[`reusable-cppcheck.yml:111`](../.github/workflows/reusable-cppcheck.yml)
- each carries `uses: org-ai-assisted/developer-meta-files/.github/actions/apt-install-with-cache@master`.

**Why CodeQL reports it**: same shape as Scorecard's
PinnedDependenciesID covered above - any `uses: <ref>@<non-sha>`
triggers. CodeQL Actions has its own copy of the rule under a
different ID.

**Why it is intentional**: the G-A-004 rationale in the
PinnedDependenciesID section above applies verbatim - first-
party `org-ai-assisted/...` cross-repo refs use `@master`
deliberately for single-source-of-truth update propagation. The
composite action lives in this same repo as the reusable
workflows that consume it; a SHA pin would create cross-file
churn on every `install.sh` change with no security gain since
the action is in the same repository under the same admin
boundary.

## What we DO act on

The Scorecard signals NOT in this list are real and worth fixing.
Notable currently-actionable categories:

- **SecurityPolicyID**: add a `SECURITY.md` to the `Kicksecure/.github`
  and `Whonix/.github` repos for org-wide default. Pending an admin
  token scoped to those orgs (same gate as
  `dm-github-org-policy --apply` against them).
- **FuzzingID**: kloak C fuzzing harness (libFuzzer on the parser)
  is the open piece; tracked in `kloak/TODO.md`. helper-scripts +
  security-misc are covered (Hypothesis / Atheris).
