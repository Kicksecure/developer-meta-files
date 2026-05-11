# GitHub Actions (AI-Assisted)

Cross-repo conventions for `.github/workflows/*.yml`. Repo-specific
security details (gating literals, fork-PR rules, persist-credentials)
remain in each repo's own `agents/github-actions-security.md`.

## Reusable workflows

Body-of-job lives in `developer-meta-files/.github/workflows/reusable-<name>.yml`
with `on: workflow_call:`. Consumer wrappers in each repo carry only
the trigger schedule + cron slot + a tiny `jobs.<id>.uses:` line.

### File-naming convention (G-A-005)

**Reusable filenames carry a `reusable-` prefix; consumer-wrapper
filenames don't.** Examples:

    .github/workflows/reusable-codeql.yml         (reusable)
    .github/workflows/codeql.yml                  (consumer wrapper)

This:

- Lets developer-meta-files self-consume its own reusables under
  the bare consumer name (`scorecard.yml` callers `./.github/
  workflows/reusable-scorecard.yml`) without inventing per-file
  workaround suffixes (`-self`, etc.).
- Makes the consumer / reusable distinction visible in the file
  list at a glance - critical when a single repo holds both kinds
  (developer-meta-files does; helper-scripts/kloak/etc. only hold
  consumers).
- Matches the convention several large orgs use internally
  (`reusable-*` is more searched-for than `_*` underscore prefix
  alternatives, per the survey logged with the rename PR).

This eliminates per-repo duplication of action SHA pins and step
bodies. Updating an action SHA on the reusable propagates to all
consumers automatically (when consumers `@master`-track) or via one
sha-bump PR per consumer (when consumers `@<sha>`-pin).

### Constraints to remember

**G-A-001: `github.*` is NOT allowed in `jobs.<id>.uses:`.**
Only `inputs`, `vars`, `needs`, and `matrix` contexts are permitted
([docs](https://docs.github.com/en/actions/sharing-automations/reusing-workflows#using-context-when-calling-a-reusable-workflow)).
The owner part of the cross-repo reference must be hardcoded or
sourced from `vars.X`.

    ## WRONG - workflow load fails:
    ##   "Unrecognized named-value: 'github'.
    ##    Located at position 1 within expression: github.repository_owner"
    uses: ${{ github.repository_owner }}/<repo>/.github/workflows/<file>.yml@<ref>

    ## OK:
    uses: Kicksecure/<repo>/.github/workflows/<file>.yml@<ref>
    ## OK (after setting org-level var):
    uses: ${{ vars.REUSABLE_OWNER }}/<repo>/.github/workflows/<file>.yml@<ref>

**G-A-002: `schedule:` cannot live under `workflow_call`.** Each
consumer's wrapper owns its own cron slot. Pick a slot offset from
the others to avoid the GitHub-side cron contention queue.

**G-A-003: `pull_request:` triggers in a PR's head don't fire on
the PR.** GitHub uses the BASE branch's workflow definition to
decide which triggers fire on `pull_request` events. Adding a new
`pull_request:` trigger in a PR will only take effect after that
PR merges to the base branch. To validate a new workflow before
merging, use `workflow_dispatch:` (which is also subject to this
"must be on default branch" rule for the dispatch endpoint to see
the workflow), OR merge to a feature branch and use that as the
base.

**G-A-004: Cross-repo `uses:` references the BASE branch of the
referenced repo by name (`@master`) or commit (`@<sha>`).** SHA
pinning gives supply-chain stability; branch tracking gives
single-source-of-truth update propagation. Both are valid; pick
per workflow based on how often the reusable changes vs. how
strict the trust boundary is.

**G-A-006: Concurrency policy - cancellable by default, singleton
for quota-limited / release-pipeline.** Every workflow declares a
top-level `concurrency:` block. Two patterns:

**Cancellable** (default for CI):

    concurrency:
      group: ${{ github.workflow }}-${{ github.ref }}
      cancel-in-progress: true

Group includes `github.ref` so each branch / PR has its own
queue; a new push on the same ref cancels the in-flight run.
Right for lint, test, codeql, cppcheck, bandit, scorecard,
claude-code-review, codex-review, build matrices.

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

Consumers of singleton reusables must NOT set
`cancel-in-progress: true` at the wrapper level: a cancelled
wrapper cancels its called workflow run, defeating the
reusable's no-cancel guarantee. Either omit `concurrency:` at
the wrapper level (the reusable's controls), or mirror the
reusable's `group + cancel=false` policy explicitly.

**Differentiated by event type** (cancel within event-type,
isolate across event-types):

    concurrency:
      group: ${{ github.workflow }}-${{ github.event_name == 'push' && 'tag' || 'pr' }}
      cancel-in-progress: true

Right when one workflow file serves both PR validation AND
release-tag builds in the same file. PR pushes all share the
`<workflow>-pr` group (latest PR push cancels older, regardless
of which PR); tag pushes all share `<workflow>-tag` (newer tag
supersedes); cross-event runs are isolated. So a tag push
cannot cancel an in-flight third-party PR validation, and a PR
push cannot cancel an in-flight 3-hour release build. Live
example: [`derivative-maker/run_automated_builder.yml`](https://github.com/org-ai-assisted/derivative-maker/blob/master/.github/workflows/run_automated_builder.yml).

**Issue-comment & PR-review-comment events** fire on the
default branch ref, not the PR head ref - so grouping by
`${{ github.ref }}` would put unrelated PRs into the same
group. For AI-review workflows that listen on those events,
the group key includes a PR/issue number disambiguator:

    group: ${{ github.workflow }}-${{ github.event.pull_request.number || github.event.issue.number || github.ref }}

See [`reusable-claude-code-review.yml`](../.github/workflows/reusable-claude-code-review.yml)
and [`reusable-codex-review.yml`](../.github/workflows/reusable-codex-review.yml)
for the live example.


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
