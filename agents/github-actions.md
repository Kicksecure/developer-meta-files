# GitHub Actions (AI-Assisted)

Cross-repo conventions for `.github/workflows/*.yml`. Repo-specific
security details (gating literals, fork-PR rules, persist-credentials)
remain in each repo's own `agents/github-actions-security.md`.

## Reusable workflows

Body-of-job lives in `developer-meta-files/.github/workflows/reusable-<name>.yml`
with `on: workflow_call:`. Consumer wrappers in each repo carry only
the trigger schedule + cron slot + a tiny `jobs.<id>.uses:` line.

### File-naming convention (G-A-005)

**Three filename prefixes mark workflow role: `reusable-`,
`consumer-`, `local-`.** Examples:

    .github/workflows/reusable-codeql.yml           (library)
    .github/workflows/consumer-codeql-actions.yml   (consumer wrapper)
    .github/workflows/local-test-build.yml          (repo-private)

- `reusable-X.yml`: library code called via `uses:`. Lives only in
  `developer-meta-files/.github/workflows/`. Never propagated. The
  path is fixed by GitHub Actions' cross-repo `uses:` resolution;
  the prefix is what disambiguates library from wrapper inside
  this single directory.
- `consumer-X.yml`: thin wrapper around a reusable. Single source
  of truth lives at
  `developer-meta-files/consumer-templates/.github/workflows/consumer-X.yml`.
  Propagated byte-identical to every opted-in consumer (including
  `developer-meta-files` itself, which is a consumer of itself).
  Hand-editing on the consumer side is wrong - changes get
  overwritten on the next propagation pass. See
  [`github-actions-consumer-templates.md`](github-actions-consumer-templates.md)
  for the architecture spec, including the `cp`-only propagation
  contract and the runtime-read mechanism for per-repo parameters.
- `local-X.yml`: workflow that lives only in the repo it is
  authored for; never propagated. Use this for repo-specific
  build/test workflows (e.g. `local-firewall-tests.yml` in
  whonix-firewall, `local-test-build.yml` in derivative-maker)
  and for hub-private workflows in `developer-meta-files`
  (`local-org-policy-live-probe.yml`,
  `local-org-tools-mock-tests.yml`).

The prefix is a filesystem signal only. GitHub's Actions UI
sidebar sorts by the workflow's in-file `name:` field, so a file
named `consumer-codeql-actions.yml` carrying `name: CodeQL Actions`
shows up in the UI as "CodeQL Actions" with no prefix visible.

The scheme buys two properties:

- One glance at `ls .github/workflows/` tells a contributor which
  files they can hand-edit (`local-*`), which are auto-managed by
  propagation (`consumer-*`) and which are library code called by
  `uses:` (`reusable-*`).
- A repo that holds a mix (`developer-meta-files` holds all three;
  most consumer repos hold `consumer-*` and `local-*` only)
  presents that mix legibly.

Eliminating per-repo duplication of action SHA pins and step
bodies is the underlying win. Updating an action SHA on the
reusable propagates to all consumers automatically (when consumers
`@master`-track) or via one sha-bump PR per consumer (when
consumers `@<sha>`-pin).

### Constraints to remember

**G-A-001: No context expressions are allowed in `jobs.<id>.uses:`.**
The value must be a literal string (with the exception of
`inputs.X` / `needs.X` / `matrix.X` / `strategy.X` references,
which ARE allowed because they're resolved before workflow
parsing). `github.*`, `vars.*`, `secrets.*`, and `env.*` are all
rejected by the workflow file validator.

    ## WRONG - workflow load fails:
    ##   "Unrecognized named-value: 'github'.
    ##    Located at position 1 within expression: github.repository_owner"
    uses: ${{ github.repository_owner }}/<repo>/.github/workflows/<file>.yml@<ref>

    ## WRONG - same failure mode, just with 'vars':
    ##   "Unrecognized named-value: 'vars'.
    ##    Located at position 1 within expression: vars.REUSABLE_OWNER"
    uses: ${{ vars.REUSABLE_OWNER }}/<repo>/.github/workflows/<file>.yml@<ref>

    ## OK - hardcoded owner. This IS the supported pattern.
    uses: Kicksecure/<repo>/.github/workflows/<file>.yml@<ref>

There is no parameterization workaround for the owner part of
`uses:`. Each first-party org (`Kicksecure`, `Whonix`,
`org-ai-assisted`) must hardcode the canonical/mirror owner it
consumes from. Cross-org consumption (e.g., Whonix-org repos
calling `Kicksecure/developer-meta-files/...`) is expressed by
hardcoding `Kicksecure/` in those consumer workflows.

**G-A-002: `schedule:` cannot live under `workflow_call`.** Each
consumer's wrapper owns its own cron slot. Pick a slot offset from
the others to avoid the GitHub-side cron contention queue.

**G-A-003: `pull_request:` triggers in a PR's head don't fire on
the PR.** GitHub uses the BASE branch's workflow definition to
decide which triggers fire on `pull_request` events. Adding a new
`pull_request:` trigger in a PR will only take effect after that
PR merges to the base branch. To validate a new workflow before
merging, merge to a feature branch and use that as the base.

**G-A-004: Cross-repo `uses:` references the BASE branch of the
referenced repo by name (`@master`) or commit (`@<sha>`).** SHA
pinning gives supply-chain stability; branch tracking gives
single-source-of-truth update propagation. Both are valid; pick
per workflow based on how often the reusable changes vs. how
strict the trust boundary is.

**G-A-006: Concurrency policy - cancellable by default, singleton
for quota-limited / release-pipeline.** Every top-level workflow
declares a top-level `concurrency:` block (reusables follow
different rules - see "Reusable-side concurrency" below). Two
patterns:

**Cancellable** (default for CI):

    concurrency:
      group: ${{ github.workflow }}-${{ github.ref }}
      cancel-in-progress: true

Group includes `github.ref` so each branch / PR has its own
queue; a new push on the same ref cancels the in-flight run.
Right for lint, test, codeql, cppcheck, bandit, scorecard,
claude-code-review, codex-review, build matrices.

`github.ref` is unique per PR (`refs/pull/N/merge`) and per tag
(`refs/tags/<tag>`), so a workflow file that handles both
`pull_request:` and `push: tags: [...]` triggers gets the right
isolation for free: different PRs do not cross-cancel, tag
pushes do not cancel PRs, and new commits on the same PR cancel
that PR's prior in-flight run. No event-type discriminator in
the group key is needed for this case.

**Reusable-side concurrency.** `github.workflow` inside a reusable
resolves to the *caller's* workflow name, so a reusable that
declares the same `${{ github.workflow }}-${{ github.ref }}` group
as its caller produces an identical lock name; Actions surfaces
this as `Canceling since a deadlock was detected for concurrency
group: ...` and cancels the run. Reusables therefore either omit
`concurrency:` entirely (the caller's cancellable group covers it
- see [`reusable-pre-push-static.yml`](../.github/workflows/reusable-pre-push-static.yml),
[`reusable-secrets-audit.yml`](../.github/workflows/reusable-secrets-audit.yml),
[`reusable-scorecard.yml`](../.github/workflows/reusable-scorecard.yml),
[`reusable-bandit.yml`](../.github/workflows/reusable-bandit.yml),
[`reusable-cppcheck.yml`](../.github/workflows/reusable-cppcheck.yml),
[`reusable-claude-code-review.yml`](../.github/workflows/reusable-claude-code-review.yml),
[`reusable-codex-review.yml`](../.github/workflows/reusable-codex-review.yml))
or differentiate the group key with a per-call input the caller
doesn't replicate ([`reusable-codeql.yml`](../.github/workflows/reusable-codeql.yml)
adds `${{ inputs.language }}` to a key the caller carries as
`${{ github.workflow }}-${{ github.ref }}`, so the two locks
differ). A naive "the reusable adds a PR/issue-number
disambiguator" pattern does NOT differentiate when the caller's
key carries the same disambiguator (both sides resolve to the
same string under `github.workflow` = caller's name); the
AI-review reusables therefore omit the block and let the
consumer wrapper own the cancellable lock.

**Singleton** (cancel=false, workflow-only group):

    concurrency:
      group: ${{ github.workflow }}
      cancel-in-progress: false

Group omits `ref` so only one run can be in flight per repo
across all branches/PRs/tags; new triggers queue server-side
rather than cancel. Right when cancelling mid-flight has a
real cost:

- **Coverity Scan**: free public tier is rate-limited to one
  build per day per project. Cancelling an in-flight upload
  burns the daily slot for no result. See
  [`reusable-coverity.yml`](../.github/workflows/reusable-coverity.yml)
  inline comment.

Singleton reusables follow the same caller-name resolution rule
as cancellable reusables (see "Reusable-side concurrency" above):
`github.workflow` inside the reusable expands to the caller's
workflow name. A reusable that declares `group: ${{ github.workflow }}`
would resolve to the caller's group key, which the caller already
holds; with `cancel-in-progress: false` the reusable would block-
wait on its own caller's lock and deadlock the run. The singleton
therefore lives on the **caller's** wrapper, and the reusable
omits `concurrency:` entirely - see
[`reusable-coverity.yml`](../.github/workflows/reusable-coverity.yml)
which carries an explicit comment to that effect, and
[`consumer-templates/.github/workflows/consumer-coverity.yml`](../consumer-templates/.github/workflows/consumer-coverity.yml)
which owns the `group: ${{ github.workflow }}` + `cancel-in-progress: false`
lock. Consumers of singleton reusables must NOT set
`cancel-in-progress: true` at the wrapper level: a cancelled
wrapper would cancel the in-flight call, defeating the no-cancel
guarantee that protects the daily-quota-limited submit.

**Issue-comment & PR-review-comment events** fire on the
default branch ref, not the PR head ref - so grouping by
`${{ github.ref }}` would put unrelated PRs into the same
group. The **consumer wrapper's** group key for AI-review
workflows therefore includes a PR/issue number disambiguator
(the disambiguator lives on the caller, not the reusable -
see "Reusable-side concurrency" above for why):

    group: ${{ github.workflow }}-${{ github.event.pull_request.number || github.event.issue.number || github.ref }}

See [`consumer-templates/.github/workflows/consumer-claude-code.yml`](../consumer-templates/.github/workflows/consumer-claude-code.yml)
and [`consumer-templates/.github/workflows/consumer-codex-review.yml`](../consumer-templates/.github/workflows/consumer-codex-review.yml)
for the live example.


**G-A-007: Cache poisoning - no broad `restore-keys:`, no
`pull_request_target` + cache.** `actions/cache` extracts archives
without integrity checks; an attacker with code-exec on a workflow
that holds `ACTIONS_RUNTIME_TOKEN` can replace cache entries
visible to the default branch for ~6h after the run. Mitigations
in this repo: (1) no `pull_request_target` triggers anywhere,
(2) fork-PR guard on every PR-triggered reusable, (3) cache keys
pinned to `hashFiles(<this workflow>)` with no catch-all
`restore-keys:` fallback, (4) cached payloads are apt `.deb`s
re-verified by `apt-get install` against fresh `Packages`
metadata. See
<https://adnanthekhan.com/2024/05/06/the-monsters-in-your-build-cache-github-actions-cache-poisoning/>.

## See also

- [`docs/scorecard-known-false-positives.md`](../docs/scorecard-known-false-positives.md)
  for the catalogue of Scorecard signals that look like findings
  but are intentional architectural choices in this org
  (DependencyUpdateToolID on consumer repos, PinnedDependenciesID
  on `@master` reusable refs, MaintainedID on fresh repos,
  SASTID transient post-CodeQL-adoption, multi-stage `FROM
  <stage>` flagged as unpinned).

## Action SHA pinning

Per repo's own `agents/github-actions-security.md`: every
third-party `uses: <action>@<sha>` carries a `# vX.Y.Z` comment with
the verifiable release tag. SHA must resolve on the upstream
reference; do not pin to a fork.

When a reusable workflow centralizes an action pin, only that one
copy needs Dependabot updates. This is the main lever to reduce
duplicate Dependabot PRs across repos.

### Org-level `sha_pinning_required` is intentionally OFF

GitHub exposes an org / repo Actions setting
`sha_pinning_required` (PUT /orgs/{org}/actions/permissions or the
per-repo equivalent). When `true`, every `uses:` reference must be
a 40-char commit SHA; floating tags (`@v4`, `@master`) fail the
run. We leave it `false` deliberately:

- First-party reusable workflows (`org-ai-assisted/...` /
  `Kicksecure/...` / `Whonix/...`) reference each other by
  branch name (`@master`) on purpose - single-source-of-truth
  update propagation, see G-A-004 above. Flipping
  `sha_pinning_required: true` would reject every such call.
- Threat-model-A in `agents/security.md` explicitly trusts
  `github.com` and the org's own repos as transport. SHA-pin
  ceremony for internal refs is over-engineering for threats
  the CI surface does not model.
- Third-party action refs are SHA-pinned individually anyway via
  the per-action discipline above; the org-wide toggle adds no
  additional protection there.

The toggle would become useful if a future threat model treats
`github.com` ref-resolution as untrusted - i.e. defense against an
attacker re-pointing `master` on an internal repo. We do not
currently model that.
