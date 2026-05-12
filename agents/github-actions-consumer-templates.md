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

Target architecture, agreed in design discussion. Some pieces are
already in place (`reusable-*.yml` library, consumer wrappers in
each repo's `.github/workflows/` under their pre-prefix names);
the rename to `consumer-*` / `local-*`, the
`consumer-templates/.github/workflows/` directory, and the
`.github/dm-consumer.yml` overlay file are pending implementation.
Treat this doc as the contract; the repo state is being brought
into line with it.

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
    |   |   |-- consumer-bandit.yml
    |   |   |-- consumer-claude-code.yml
    |   |   |-- consumer-codeql-actions.yml
    |   |   |-- consumer-codex-review.yml
    |   |   |-- consumer-pre-push-static.yml
    |   |   |-- consumer-scorecard.yml
    |   |   `-- consumer-secrets-audit.yml
    |   `-- actions/
    |       |-- install-deps/
    |       `-- shellcheck/
    `-- consumer-templates/
        `-- .github/
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
`pre-push-static.yml`, `secrets-audit.yml`) all become
`consumer-*.yml`. The unprefixed hub-private workflows
(`live.yml`, `policy-live.yml`, `test-github-org-tools.yml`)
become `local-*.yml` with names that describe what they actually
do.

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
    ## Top-level keys mirror the reusable basename without
    ## the 'reusable-' prefix.
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
tree), not by file-extension matching, so no per-repo paths
config is needed.

## Reusable-side runtime read pattern

The parameterized reusables (`reusable-coverity.yml`,
`reusable-cppcheck.yml`, `reusable-codeql.yml` in c-cpp mode)
include a config-load step shortly after the consumer-repo
checkout. Reference shape:

    - name: Load per-repo config from .github/dm-consumer.yml
      id: cfg
      run: |
        set -o errexit
        set -o nounset
        set -o pipefail
        cfg_file=".github/dm-consumer.yml"
        if [ ! -f "${cfg_file}" ]; then
          printf '%s\n' "error: ${cfg_file} not found; reusable-coverity requires per-repo config" >&2
          exit 1
        fi
        for key in apt-packages build-command project-name canonical-repos; do
          value="$(yq ".coverity[\"${key}\"]" "${cfg_file}")"
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
          printf '%s=%s\n' "${key}" "${value}" >> "${GITHUB_OUTPUT}"
        done

Subsequent steps in the reusable reference
`${{ steps.cfg.outputs.<key> }}`. The reusable's
`workflow_call.inputs:` block for those values goes away - they
are discovered, not passed.

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

Three error classes the reusable's config-load step distinguishes:

1. `.github/dm-consumer.yml` not present at all - hard error,
   exit 1. The wrapper is installed but per-repo values are not
   configured.
2. dm-consumer.yml present but missing the template's section, or
   missing a required key within that section - hard error, exit
   1. Print the missing path (e.g. `coverity.project-name`).
3. dm-consumer.yml has a section for a template that is not
   currently installed - not detected here (the reusable for an
   uninstalled template never runs). This is the orphan-config
   case; it does no harm.

Hard-fail at workflow runtime is the runtime mirror of the
pre-`cp` validation approach we explicitly rejected (which would
have required the propagation tool to parse yml). Loud failure at
workflow start beats silent drift.

## Wrapper shape (byte-identical example)

The full `consumer-coverity.yml` template, byte-identical across
every consumer including `developer-meta-files` itself:

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

No `with:` block on the reusable call - the reusable reads its
own per-repo config at workflow runtime.

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
- The same propagation tool that maintains the consumer copies
  also maintains the hub's own copies, because the hub is a
  consumer of itself. No special-case logic for the hub.

## See also

- [`github-actions.md`](github-actions.md) for cross-repo
  conventions, the G-A-* rule numbering, and the file-prefix
  scheme (G-A-005).
- [`github-policy-canonical-vs-mirror.md`](github-policy-canonical-vs-mirror.md)
  for why Coverity `project-name` cannot be derived from the
  GitHub repo name.
