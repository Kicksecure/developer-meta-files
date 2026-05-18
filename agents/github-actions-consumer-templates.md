# GitHub Actions: consumer-template architecture (AI-Assisted)

How `developer-meta-files` propagates consumer-side workflow
wrappers to the rest of the org with single-source-of-truth and
zero drift, and how parameterized templates carry per-repo values
without the propagation tool ever growing into a script that
parses or writes yml.

The prefix conventions and the wider "reusable vs consumer vs
local" file-naming rules live in
[`github-actions.md`](github-actions.md) G-A-005. This doc is the
companion spec covering the propagation contract and the per-repo
parameter mechanism in detail.

## Status

Implemented. The three-prefix file-naming convention
(`reusable-` / `consumer-` / `local-`), the
`consumer-templates/.github/workflows/` canonical-source
directory, the `.github/dm-consumer.yml` overlay file in
parameterized consumers, and the reusable-side runtime read
pattern are all live. Coverity / cppcheck / codeql / bandit
all read per-repo overrides at workflow runtime; the propagation
tool `pkg_update_consumer_workflows` does pure-`cp` byte-
identical updates of every `consumer-*.yml` file already present
on a consumer's `.github/workflows/`, and of `.github/dependabot.yml`
sourced from `consumer-templates/.github/dependabot.yml`.

Validated end-to-end on `kloak` (`workflow_dispatch` of
`consumer-coverity.yml`, full pipeline through cov-build +
Coverity Scan submission accepted). See PRs #67 through #71 on
this repo plus the per-consumer PRs referenced from them.

## Directory layout

    developer-meta-files/
    |-- .github/
    |   |-- workflows/
    |   |   |   ## Library - called via `uses:`. Path is fixed.
    |   |   |-- reusable-bandit.yml
    |   |   |-- reusable-claude-code-review.yml
    |   |   |-- reusable-codeql.yml
    |   |   |-- reusable-codex-review.yml
    |   |   |-- reusable-coverity.yml
    |   |   |-- reusable-cppcheck.yml
    |   |   |-- reusable-pre-push-static.yml
    |   |   |-- reusable-scorecard.yml
    |   |   |-- reusable-secrets-audit.yml
    |   |   |   ## Hub-private - never propagated.
    |   |   |-- local-org-policy-live-probe.yml
    |   |   |-- local-org-policy-live-audit.yml
    |   |   |-- local-org-tools-mock-tests.yml
    |   |   |   ## Auto-managed copies of the templates below.
    |   |   |   ## developer-meta-files is a consumer of itself.
    |   |   |   ## Note: consumer-scorecard.yml NOT installed in
    |   |   |   ## the hub - Scorecard is org-wide-opted-out of
    |   |   |   ## every repo except derivative-maker (the
    |   |   |   ## canonical baseline). consumer-coverity.yml,
    |   |   |   ## consumer-cppcheck.yml, consumer-codeql-cpp.yml
    |   |   |   ## NOT installed - the hub has no C/C++.
    |   |   |-- consumer-bandit.yml
    |   |   |-- consumer-claude-code.yml
    |   |   |-- consumer-codeql-actions.yml
    |   |   |-- consumer-codeql-python.yml
    |   |   |-- consumer-codex-review.yml
    |   |   |-- consumer-pre-push-static.yml
    |   |   `-- consumer-secrets-audit.yml
    |   `-- actions/
    |       |-- install-deps/
    |       `-- shellcheck/
    `-- consumer-templates/
        `-- .github/
            |   ## Single source of truth for .github/dependabot.yml.
            |   ## Byte-identical across every consumer (including
            |   ## the hub itself - dmf is a self-consumer).
            |-- dependabot.yml
            `-- workflows/
                |   ## Single source of truth for every
                |   ## consumer-*.yml propagated across the org.
                |-- consumer-bandit.yml
                |-- consumer-claude-code.yml
                |-- consumer-codeql-actions.yml
                |-- consumer-codex-review.yml
                |-- consumer-coverity.yml         ## parameterized
                |-- consumer-cppcheck.yml         ## parameterized
                |-- consumer-codeql-cpp.yml       ## parameterized
                |-- consumer-pre-push-static.yml
                |-- consumer-scorecard.yml
                `-- consumer-secrets-audit.yml

`developer-meta-files/.github/workflows/` does NOT carry consumer
wrappers for `coverity`, `cppcheck`, or `codeql-cpp`. The hub has
no C/C++ to scan; those parameterized templates live in
`consumer-templates/` and propagate only to consumers that have
those workflows installed.

The unprefixed wrappers from before the rename (`claude-code.yml`,
`codex-review.yml`, `scorecard.yml`, `codeql-actions.yml`,
`pre-push-static.yml`, `secrets-audit.yml`) are now `consumer-*.yml`.
The unprefixed hub-private workflows (formerly `live.yml`,
`policy-live.yml`, `test-github-org-tools.yml`) are now
`local-org-policy-live-probe.yml`,
`local-org-policy-live-audit.yml`, and
`local-org-tools-mock-tests.yml` respectively.

## Propagation contract

The propagation tool (`pkg_update_consumer_workflows`) does ONE
thing: `cp` from
`developer-meta-files/consumer-templates/.github/workflows/consumer-X.yml`
to each consumer's `.github/workflows/consumer-X.yml`.

It does NOT:

- read, parse, or substitute placeholders in yml content,
- generate yml files,
- decide which consumers opt in or out,
- merge per-repo overlays.

Two contracts follow from "propagation is pure `cp`":

### Opt-in by file presence

The presence of `consumer-X.yml` in a consumer's
`.github/workflows/` IS the opt-in signal. Adding the file opts
the repo in; deleting the file opts it out. The propagation tool
refreshes only files that already exist on the consumer side; it
does not create new files.

Bootstrapping a new wrapper into a consumer is a deliberate
one-time act (use `dm-packaging-helper-script`, or hand-add the
file). Maintenance after bootstrap is automated.

### No allowlists, no manifest, no opt-out flag

Earlier iterations of this design carried a central `manifest.yml`
listing which templates apply where. It was dropped: a manifest
in the hub gets stale, and "is this template installed here?" is
already answered authoritatively by the consumer's filesystem.

`.github/dm-consumer.yml` (described below) carries only per-repo
PARAMETER values for parameterized templates, never opt-in or
opt-out flags.

## `.github/dependabot.yml` propagation

Canonical at `consumer-templates/.github/dependabot.yml` carries
the `github-actions` ecosystem only. Propagation:

- `pkg_update_consumer_workflows` refreshes the file when
  already present (UPDATE-if-exists).
- `pkg_install_dependabot_yml` bootstraps it when missing, if
  the consumer has `.github/workflows/`. Idempotent.

Both honour a `## propagation: manual` header marker on the
consumer's file and skip when present.

### Per-repo manual `dependabot.yml`

Repos with a Dockerfile at a non-root path hand-maintain their
own:

| Repo | Dockerfile | dependabot `directory:` |
| --- | --- | --- |
| `derivative-maker` | `docker/Dockerfile` | `"docker"` |
| `helper-scripts` | `.clusterfuzzlite/Dockerfile` | `".clusterfuzzlite"` |

Place `## propagation: manual` as the first content line. Keep
the `github-actions` `updates:` block byte-identical to the
canonical; only the `docker` block diverges.

Dependabot's `docker` ecosystem watches Dockerfile `FROM` lines
only, not workflow `container:` / `image:` pins; those are
manually maintained per
[`github-actions.md`](github-actions.md).

## Scheduling in byte-identical templates

Byte-identical propagation forbids per-repo cron-slot rewriting
at propagation time, which collides with the per-repo cron-slot
guidance in [`github-actions.md`](github-actions.md) G-A-002.
Resolution: every byte-identical consumer template with
`schedule:` - universal or parameterized - uses a uniform
org-wide cron slot baked into the template. GitHub's cron queue
will serialize the org-wide simultaneous fires; that contention
is accepted.

Three current examples:

- `consumer-codeql-actions.yml` is cronless on purpose - push /
  pull_request / workflow_dispatch cover the scan-on-change
  cases, and rule-refresh re-scans are kicked manually.
- `consumer-scorecard.yml` carries a single org-wide cron slot.
  Scorecard's value-to-noise ratio is low (many false positives,
  non-actionable signals); concentrating the runs at one time
  is not worth the per-repo-rewrite complexity it would take to
  spread them.
- `consumer-coverity.yml` (parameterized) carries a single
  org-wide cron slot plus tag-push triggers. Coverity's free
  public tier rate-limits to one build per day per project, so
  serialized fires within the queue are harmless - each project
  is bounded by its own quota, not by the cron concentration.

If a future template has stronger scheduling needs, the right
answer is to either (a) eliminate the cron (move to
event-triggered only), or (b) accept the uniform slot. Per-repo
rewriting at propagation time is not a path back into scope.

## Per-repo parameters: `.github/dm-consumer.yml`

Some templates need per-repo values that genuinely cannot be
uniform across the org. Coverity's scan.coverity.com
`project-name` is the canonical example - not derivable from the
GitHub repo name (see
[`github-policy-canonical-vs-mirror.md`](github-policy-canonical-vs-mirror.md)
for why upstream-org-based derivation was tried and rejected).

Those values live in `.github/dm-consumer.yml` in each consuming
repo. Schema:

    ## .github/dm-consumer.yml
    ## Top-level keys mirror the consumer-template basename
    ## without the 'consumer-' prefix.
    ## Sub-keys mirror the values the reusable consumes.

    coverity:
      apt-packages:    "libevdev-dev libinput-dev libwayland-dev libxkbcommon-dev pkg-config"
      build-command:   "./cov-analysis/bin/cov-build --dir cov-int make"
      project-name:    "Whonix/kloak"
      canonical-repos: "Whonix/kloak,org-ai-assisted/kloak"

    cppcheck:
      paths: "src"

    codeql-cpp:
      build-command: "bash build.sh"

The file is read at WORKFLOW RUNTIME by the relevant
`reusable-X.yml`, not at propagation time. This preserves the
pure-`cp` propagation contract.

Universal templates (`consumer-claude-code.yml`,
`consumer-codex-review.yml`, `consumer-scorecard.yml`,
`consumer-codeql-actions.yml`, `consumer-pre-push-static.yml`,
`consumer-secrets-audit.yml`, `consumer-bandit.yml`) carry no
per-repo state. A consumer that only installs universal templates
does not need a `.github/dm-consumer.yml` file at all.

`consumer-bandit.yml` is universal even though much Python in
this codebase ships without `.py` extensions (genmkfile
package-tag naming, executables with shebang lines only): the
reusable discovers Python via shebang scan (`#!.*python` over the
tree) AND `.py` extension, so no per-repo paths config is needed.
The discovery script lives at `ci/bandit-discover-python.sh` in
this repo.

## Parameter ownership across reusable inputs

For every existing `workflow_call.input` touched by this
architecture, this table classifies the input as one of:

- **dm-consumer.yml**: per-repo value, read from
  `.github/dm-consumer.yml` at workflow runtime.
- **hardcoded in reusable**: same value org-wide; lives as the
  reusable's `default:`. The wrapper does not override.
- **hardcoded in wrapper**: same value across all consumers of
  a given template, baked into the byte-identical wrapper's
  `with:` block. Different templates calling the same reusable
  may bake different values (e.g. `language: c-cpp` vs
  `language: actions`).
- **removed**: input is deleted from the reusable's
  `workflow_call.inputs:`.

Wrappers are byte-identical across their consumers, so no input
can be "passed by the consumer wrapper to a per-repo value" -
the only per-repo channel is `.github/dm-consumer.yml`.

These categorizations describe the **byte-identical wrapper
contract**: what consumer-template wrappers are allowed to do.
Direct callers of a reusable from outside that contract - a
hand-written `local-*.yml` in some repo that calls
`reusable-coverity.yml` directly, for example - can still pass
any inputs that remain exposed by the reusable. Values moved
to dm-consumer.yml (the "dm-consumer.yml" category) are removed
from `workflow_call.inputs:` entirely, so they are not
direct-call inputs either; only the surviving
`workflow_call.inputs` are. Categories labelled "hardcoded in
reusable" and "hardcoded in wrapper" describe what the
byte-identical wrapper does, not whether the reusable's input
surface is technically overridable.

### `reusable-bandit.yml` (consumer-bandit.yml is universal)

- `paths`: **removed**. Discovery moves to shebang scan; no
  per-repo path list is needed.
- `severity-level`: **hardcoded in reusable** at the current
  default ("medium").
- `confidence-level`: **hardcoded in reusable** at the current
  default ("medium").
- `skips`: **removed**. Per-repo suppressions move to `# nosec`
  comments in source. Open follow-up: if a real use case for
  per-repo skip lists appears post-rollout, promote
  `bandit.skips` to dm-consumer.yml at that point.
- `prepare-command`: **removed**. Bandit does not need build
  setup; the input is unused in practice.
- `timeout-minutes`: **hardcoded in reusable** at the current
  default (10).

### `reusable-coverity.yml` (consumer-coverity.yml is parameterized)

- `apt-packages`: **dm-consumer.yml** (optional; empty = no
  apt-installs, e.g. Python-only Coverity repos).
- `build-command`: **dm-consumer.yml** (optional; empty defers
  to the reusable's Python helper).
- `project-name`: **dm-consumer.yml** (required).
- `canonical-repos`: **dm-consumer.yml** (required). The move
  from reusable input to runtime read changes where the gate
  runs; see "Coverity canonical-repos gate placement" below.
- `timeout-minutes`: **hardcoded in reusable** at the current
  default (30).
- `dry-run`: **hardcoded in reusable** at `false`. No wrapper
  override. Manual dry-runs happen in a development branch by
  editing the wrapper temporarily; the production path never
  submits in dry-run mode.

### `reusable-cppcheck.yml` (consumer-cppcheck.yml is parameterized)

- `paths`: **dm-consumer.yml** (required).
- `enable`: **hardcoded in reusable** at the current default
  ("warning,performance,portability"). Repos that want broader
  scope ("style", etc.) contribute the default change; per-repo
  override is not supported.
- `extra-args`: **removed**. Promote to dm-consumer.yml if a
  real need appears post-rollout.
- `prepare-command`: **dm-consumer.yml** (optional). Source-tree
  prep (generating headers, running `./configure`, copying files
  into place) before cppcheck runs. Not the place for apt
  installs - those would be uncached. If a real apt-deps need
  appears, promote `cppcheck.apt-packages` to dm-consumer.yml at
  that point with its own cache key.
- `timeout-minutes`: **hardcoded in reusable** at the current
  default (15).

### `reusable-codeql.yml` (consumer-codeql-cpp.yml and consumer-codeql-actions.yml)

- `language`: **hardcoded in wrapper**.
  `consumer-codeql-cpp.yml` passes `"c-cpp"`;
  `consumer-codeql-actions.yml` passes `"actions"`. Each template
  is byte-identical across its consumers; the two templates
  differ from each other by exactly this value.
- `prepare-command`: **dm-consumer.yml** (optional), only for
  c-cpp. `consumer-codeql-actions.yml` does not pass it.
- `build-mode`: **hardcoded in wrapper**. `"manual"` for c-cpp;
  `"none"` for actions.
- `build-command`: **dm-consumer.yml** (required), only for
  c-cpp.
- `queries`: **hardcoded in reusable** at the current default
  (`"security-and-quality"`).
- `timeout-minutes`: **hardcoded in reusable** at the current
  default (30).

### Coverity canonical-repos gate placement

The current `reusable-coverity.yml` uses
`inputs.canonical-repos` in `jobs.<id>.if:`, evaluated before
any step runs. Moving `canonical-repos` into `.github/dm-consumer.yml`
means the value becomes a step output
(`steps.cfg.outputs.canonical_repos` - underscored, per the
output-naming convention below), which is not available to the
same job's `if:` - step outputs only exist after the step
completes.

Resolution: a step-level gate replaces the job-level gate. After
the config-load step, a "canonical-repos gate" step compares
`github.repository` against the loaded list and emits a step
output. All expensive subsequent steps (Coverity download,
build, submit) carry
`if: steps.gate.outputs.allowed == 'true'`. A non-canonical run
completes with overall status `success` (the gate step itself
succeeds; the expensive steps are skipped). There is no
first-class "neutral" job result for a shell-driven gate; the
expensive-steps-skipped success state is operationally
equivalent.

This is security-relevant: the current gate prevents a fork's
Coverity workflow from burning the upstream project's daily
free-tier slot. The replacement preserves that property - the
gate runs before any download or submission step, and the
submit step's secrets path is never reached on a non-canonical
run.

Behavior change worth flagging: today's reusable's `if:`
expression treats `workflow_dispatch` as an unconditional bypass
of `canonical-repos` (`github.event_name == 'workflow_dispatch'
|| inputs.canonical-repos == '' || contains(...)`). The step-
level gate is intentionally stricter: a manual
`workflow_dispatch` on a non-canonical repo no longer bypasses
the gate. The forked-side maintainer doing a manual dispatch
would have burned runner time for nothing anyway (the org's
COVERITY_SCAN_TOKEN is not available to forks), and the
upstream's quota is now never at risk from cross-fork manual
triggers.

Implementation detail: today's `reusable-coverity.yml` sets
`COVERITY_TOKEN` and `COVERITY_EMAIL` in `jobs.<id>.env:` at
job level (lines 196-199 on master at time of writing). With a
job-level `if:` gate, this is fine - the whole job is skipped on
a non-canonical run, env included. With a step-level gate, the
job DOES run, so job-level env would leak the secret values into
every step including the gate itself and any non-gated step
before it. The rewrite must move `COVERITY_TOKEN` /
`COVERITY_EMAIL` out of `jobs.<id>.env:` and onto the individual
steps that need them (Coverity download / build / submit), each
gated by `if: steps.gate.outputs.allowed == 'true'`. Otherwise
the spec's "secrets path is never reached on a non-canonical
run" claim is not actually true.

The cost vs. the job-level gate is ~30 seconds of runner time
per non-canonical attempt (runner spin-up + checkout +
config-load + gate eval), which is negligible against the
multi-hour cost of an actual Coverity build.

## Reusable-side runtime read pattern

The parameterized reusables (`reusable-coverity.yml`,
`reusable-cppcheck.yml`, `reusable-codeql.yml` in c-cpp mode)
include a config-load step shortly after the consumer-repo
checkout. Reference shape:

    - name: Install yq
      ## The implementation installs Ubuntu/Debian's apt-packaged
      ## `yq` (kislyuk's python-yq jq wrapper) and uses that
      ## interface explicitly. The `// ""` defaults and `-r` raw
      ## output below are written for that implementation. The
      ## parameterized reusables should pin `runs-on: ubuntu-24.04`
      ## (rather than `ubuntu-latest`) so this contract is not
      ## silently broken if a future Ubuntu LTS swaps in
      ## mikefarah/yq via the apt package.
      run: |
        sudo --non-interactive apt-get update --error-on=any
        sudo --non-interactive apt-get install --yes --no-install-recommends yq

    - name: Load per-repo config from .github/dm-consumer.yml
      id: cfg
      ## yml keys are hyphenated; $GITHUB_OUTPUT names below are
      ## underscored, because GitHub Actions expression syntax
      ## parses `outputs.foo-bar` as subtraction, not as a
      ## hyphenated property reference. Underscored output names
      ## let downstream steps use plain dot syntax
      ## (`${{ steps.cfg.outputs.project_name }}`) rather than
      ## the bracket form (`steps.cfg.outputs['project-name']`).
      run: |
        set -o errexit
        set -o nounset
        set -o pipefail
        cfg_file=".github/dm-consumer.yml"
        if [ ! -f "${cfg_file}" ]; then
          printf '%s\n' "error: ${cfg_file} not found; reusable-coverity requires per-repo config" >&2
          exit 1
        fi

        ## Required keys: missing or empty -> hard error.
        for key in project-name canonical-repos; do
          value="$(yq -r ".coverity[\"${key}\"]" "${cfg_file}")"
          if [ "${value}" = 'null' ] || [ -z "${value}" ]; then
            printf '%s\n' "error: ${cfg_file} missing coverity.${key}" >&2
            exit 1
          fi
          case "${value}" in
            *$'\n'*|*$'\r'*)
              printf '%s\n' "error: coverity.${key} contains newline; not allowed" >&2
              exit 1
              ;;
          esac
          out_name="${key//-/_}"
          printf '%s=%s\n' "${out_name}" "${value}" >> "${GITHUB_OUTPUT}"
        done

        ## Optional keys: missing -> empty string, which downstream
        ## steps interpret as "use the reusable's built-in default
        ## behavior" (no apt-install step, no custom build command).
        for key in apt-packages build-command; do
          value="$(yq -r ".coverity[\"${key}\"] // \"\"" "${cfg_file}")"
          case "${value}" in
            *$'\n'*|*$'\r'*)
              printf '%s\n' "error: coverity.${key} contains newline; not allowed" >&2
              exit 1
              ;;
          esac
          out_name="${key//-/_}"
          printf '%s=%s\n' "${out_name}" "${value}" >> "${GITHUB_OUTPUT}"
        done

Subsequent steps in the reusable reference the underscored
output names, e.g. `${{ steps.cfg.outputs.project_name }}` and
`${{ steps.cfg.outputs.canonical_repos }}`. Only the
**dm-consumer.yml-owned** values disappear from the reusable's
`workflow_call.inputs:` - they are discovered, not passed.
Values classified as **hardcoded in wrapper** (e.g. codeql's
`language`, `build-mode`) stay as `workflow_call.inputs` and ARE
passed via `with:` from the byte-identical wrapper; values
classified as **hardcoded in reusable** (e.g. coverity's
`timeout-minutes`, `dry-run`) stay as `workflow_call.inputs`
with the reusable's `default:` and are never passed by the
wrapper.

### `$GITHUB_OUTPUT` is not a secret-masking surface

Anything written to `$GITHUB_OUTPUT` is readable by subsequent
steps without masking. GitHub's secret-redaction is a separate
log-side mechanism that string-matches registered secret values.
For the config-load step this is fine because every value in
`.github/dm-consumer.yml` is checked-in public configuration.
Keep it that way: never write `secrets.*` to `$GITHUB_OUTPUT`.
Pass secrets through `secrets:` on the reusable call or `env:`
on the consuming step instead.

The newline-rejecting `case` block in the example above protects
against `$GITHUB_OUTPUT` format injection - a value containing
`\n` or `\r` would otherwise inject phantom output keys.

## Hard-fail validation

Each `dm-consumer.yml` key is annotated **(required)** or
**(optional)** in the parameter-ownership table above. The
reusable's config-load step uses those annotations to distinguish
four error / non-error classes:

1. `.github/dm-consumer.yml` not present at all - hard error,
   exit 1. The wrapper is installed but per-repo values are not
   configured.
2. dm-consumer.yml present but missing the template's section
   entirely - hard error, exit 1. The wrapper is installed but
   the section that drives it is absent.
3. Section present but missing a key annotated **(required)** -
   hard error, exit 1. Print the missing path (e.g.
   `coverity.project-name`).
4. Section present but missing a key annotated **(optional)** -
   not an error. The reusable treats the value as empty and
   falls through to its built-in default behavior (e.g. empty
   `coverity.apt-packages` skips the apt-install step;
   empty `cppcheck.prepare-command` skips the source-tree prep
   step).

A dm-consumer.yml section for a template that is not currently
installed is not detected here (the reusable for an uninstalled
template never runs). This is the orphan-config case; it does no
harm.

Hard-fail at workflow runtime is the runtime mirror of the
pre-`cp` validation approach we explicitly rejected (which would
have required the propagation tool to parse yml). Loud failure at
workflow start beats silent drift.

## Wrapper shape (byte-identical example)

The full `consumer-coverity.yml` template, byte-identical across
every opted-in consumer (every repo that has
`consumer-coverity.yml` installed in its `.github/workflows/`).
`developer-meta-files` itself does not install this template -
the hub has no C/C++ to scan - so `consumer-coverity.yml` only
lives in `consumer-templates/.github/workflows/` on the hub,
never in `.github/workflows/`:

    ## Copyright (C) 2026 - 2026 ENCRYPTED SUPPORT LLC <adrelanos@whonix.org>
    ## See the file COPYING for copying conditions.

    ## AI-Assisted

    ## Managed by pkg_update_consumer_workflows. Byte-identical
    ## across consumers; this file is `cp`-ed from
    ## developer-meta-files/consumer-templates/.github/workflows/consumer-coverity.yml.
    ## Per-repo values are read by the reusable from
    ## .github/dm-consumer.yml at workflow runtime.
    ##
    ## Reusable docs:
    ## https://github.com/org-ai-assisted/developer-meta-files/blob/master/.github/workflows/reusable-coverity.yml

    name: Coverity

    on:
      push:
        tags:
          - '*'
      schedule:
        - cron: '0 4 * * 5'
      workflow_dispatch:

    permissions:
      contents: read

    ## Coverity singleton policy: G-A-006 in github-actions.md.
    ## Cancelling mid-flight wastes the daily free-tier slot.
    concurrency:
      group: ${{ github.workflow }}
      cancel-in-progress: false

    jobs:
      coverity:
        uses: org-ai-assisted/developer-meta-files/.github/workflows/reusable-coverity.yml@master
        secrets:
          COVERITY_SCAN_TOKEN: ${{ secrets.COVERITY_SCAN_TOKEN }}
          COVERITY_SCAN_EMAIL: ${{ secrets.COVERITY_SCAN_EMAIL }}
        permissions:
          contents: read

No `with:` block on the reusable call in this template:
coverity has no hardcoded-in-wrapper inputs (no language /
build-mode analog) and every per-repo value is read by the
reusable from `.github/dm-consumer.yml` at workflow runtime.
Other templates may have a `with:` block - `consumer-codeql-cpp.yml`
passes `language: c-cpp` and `build-mode: manual` because those
are classified hardcoded-in-wrapper - and that block is itself
byte-identical across the template's consumers.

## What this design buys

- Single source of truth for every `consumer-*.yml` in the org.
- Zero drift across consumers: any change to the template
  propagates on the next `pkg_update_consumer_workflows` pass.
- Propagation tool stays trivial: `cp` only, no yml parsing, no
  yml writing.
- Per-repo state lives next to the workflow that needs it
  (`.github/dm-consumer.yml` in the consumer), not in a
  centralized manifest that ages out of sync.
- Opt-in is filesystem-driven and self-documenting
  (`ls .github/workflows/` answers "what is installed here?").
- The same propagation tool also maintains the hub's own
  installed `consumer-*` copies. The hub opts into only the
  templates that make sense for it (the universal set, no C/C++
  templates), using the same file-presence rule as every other
  consumer. No special-case logic for the hub.

## See also

- [`github-actions.md`](github-actions.md) for cross-repo
  conventions, the G-A-* rule numbering, and the file-prefix
  scheme (G-A-005).
- [`github-policy-canonical-vs-mirror.md`](github-policy-canonical-vs-mirror.md)
  for why Coverity `project-name` cannot be derived from the
  GitHub repo name.
