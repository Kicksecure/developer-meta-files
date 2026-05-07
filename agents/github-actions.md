# GitHub Actions (AI-Assisted)

Cross-repo conventions for `.github/workflows/*.yml`. Repo-specific
security details (gating literals, fork-PR rules, persist-credentials)
remain in each repo's own `agents/github-actions-security.md`.

## Reusable workflows

Body-of-job lives in `developer-meta-files/.github/workflows/<name>.yml`
with `on: workflow_call:`. Consumer wrappers in each repo carry only
the trigger schedule + cron slot + a tiny `jobs.<id>.uses:` line.

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

## Action SHA pinning

Per repo's own `agents/github-actions-security.md`: every
third-party `uses: <action>@<sha>` carries a `# vX.Y.Z` comment with
the verifiable release tag. SHA must resolve on the upstream
reference; do not pin to a fork.

When a reusable workflow centralizes an action pin, only that one
copy needs Dependabot updates. This is the main lever to reduce
duplicate Dependabot PRs across repos.
