# TODO (developer-meta-files)

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

### 11. `workflow_run` cascade for diagnostics

When a workflow fails opaquely (the usability-misc
`startup_failure` was the canonical case), a `workflow_run` event-
triggered "diagnose-failure" workflow could fetch the workflow
file, scan with our self-validator, post a check_run annotation
explaining the likely cause. Closes the loop on "API doesn't
surface annotations".
