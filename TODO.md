# TODO (developer-meta-files)

Tracker for the workflow / CI hardening ideas not yet started or
in-progress. Done items live in commit history; this file lists
what's queued. Discuss + decide scope per item before opening PRs.


## Tier 2 - medium value, medium effort

### 5. Org-wide `dependabot.yml` consistency

Some repos bundle action bumps into one grouped PR per cycle
(kloak landed this pattern earlier); others have no
`dependabot.yml` at all; some have divergent schedules and
allow-lists. Standardize either via a `.github/dependabot.yml`
baseline applied to each repo, or a validator check that flags
divergence.

### 6. `$GITHUB_STEP_SUMMARY` for rich PR status

Workflows like coverity / codeql / shellcheck could emit a one-
line summary table to `$GITHUB_STEP_SUMMARY`, which renders as a
markdown panel under the run. Currently zero workflows use it.
Useful surface for "5 issues found / 0 errors / 3 warnings / 2
info" in the PR check UI.

### 7. PR template (`.github/PULL_REQUEST_TEMPLATE.md`)

Standardize PR descriptions org-wide. Sections: Summary, Why,
Test plan, Related. Currently each PR opens with whatever
structure the author chose.

### 8. Workflow trigger normalization

Some workflows trigger on push to master only, some on every
push; some have `branches: [master]` filter, some don't.
Document the policy (most CI on push-any-branch + pull_request
to master; scheduled workflows pick a cron offset; release-
builders only on tags) and audit for compliance.

### 9. Inputs validation in `workflow_dispatch`

`codex-review.yml` accepts a `pr_ref` input but doesn't validate
format. Adversarial values could affect downstream behavior.
Validate in the reusable.


## Tier 3 - lower priority / requires consensus

### 10. Pin all containers to digest

`debian:trixie@sha256:...` form. Currently we pin actions but not
containers. derivative-maker's `lint.yml` does pin
(`debian:trixie@sha256:35b8ff...`); others use `debian:trixie` /
`debian:stable` floating. Supply-chain analogue.

### 11. `workflow_run` cascade for diagnostics

When a workflow fails opaquely (the usability-misc
`startup_failure` was the canonical case), a `workflow_run` event-
triggered "diagnose-failure" workflow could fetch the workflow
file, scan with our self-validator, post a check_run annotation
explaining the likely cause. Closes the loop on "API doesn't
surface annotations".

### 12. Reusable-workflow `@<sha>` pinning (vs current `@master`)

Currently first-party reusables are `@master`-tracked. Pinning
each consumer reference to `@<sha>` with Dependabot bumps would
be stronger supply chain but adds PR churn. G-A-004 explicitly
accepts either; document the trade-off explicitly and pick a
default.

### 13. Unused-workflow audit

Each repo has accumulated workflows; some may not have run in N
days. Audit + propose removal for genuinely-dead workflows
(e.g., the `codex-review` stub which is `if: false` everywhere).
