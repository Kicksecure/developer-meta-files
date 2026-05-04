# github-org-* / dm-* project rules (AI-Assisted)

Project-specific rules for the assisted-by-ai/developer-meta-files
github-org-* / dm-* tool family. Companion to:

- [bash-style-guide.md](bash-style-guide.md) - general bash style
  under R-NNN, applies to every script in the org.
- [security.md](security.md) - the threat model these rules
  defend.

Rules use G-NNN numbering so they can be cited alongside R-NNN
bash rules in code review.

Each rule: a one-line statement (the bold first sentence), an
optional "Why" rationale, an optional code example. Skim the
bold lines to audit a diff; read the Why for context.

## Project-rule spot-check (github-org-* / dm-* surface)

    [ ] API-derived string into URL/file/git/curl arg ->
        ghorg_validate_name (G-001) or numeric regex + length
        cap (G-002)
    [ ] API-derived string into printf/log -> ghorg_safe_print
        (G-003)
    [ ] No new <( ... ) process substitution feeding a read loop
        without a documented reason (audit checklist in G-doc)
    [ ] No new '&' background worker mutating shared state
        without a tempfile (R-052, G-033)
    [ ] New non-2xx success status (e.g., DELETE 404) passed as
        the 5th arg to policy_api_call (G-034)

## Mock-API test spot-check

    [ ] Tests capture combined output via 2>&1 (G-041; bare
        $(cmd) is empty after the printf->log conversion)
    [ ] No '^prefix' anchored greps that target the log-line
        prefix; use --fixed-strings substrings or exit-code
        checks (G-042)
    [ ] Prefer exit-code-based assertions to output-format-based
        ones (G-043)
    [ ] Reinstall ALL changed binaries before running the suite
        locally - 'sudo cp' the full set or 'genmkfile install'.
        A partial install masks regressions because the tool
        still in /usr/bin is the unrefactored one.
    [ ] Run the FULL ci/test-github-org-tools.sh suite, not just
        the file matching the changed surface. Cross-file
        contracts break otherwise.

## Threat boundary: GitHub REST API responses

Every byte returned by `api.github.com` (or whatever `${GHORG_API}`
points at) is treated as untrusted. R-140 in the bash guide states
the principle abstractly; G-001 through G-004 below implement it
for this surface using `ghorg_validate_name` and `ghorg_safe_print`.


## API-derived strings

**G-001: Validate API-derived names before identifier sinks.**
Every name extracted from the GitHub API must pass through
`ghorg_validate_name` (allowlist `^[A-Za-z0-9._-]+$`, length cap,
reserved-name and `..` rejection) before flowing into a URL path,
file path, git/curl arg, or command-line arg.

Why: a hostile or replayed API endpoint can return arbitrary bytes;
those bytes flow through string interpolation into shell-level
sinks. The validator defines exactly what the consumer accepts.

**G-002: Validate numeric IDs with regex + length cap.** API-
derived IDs flowing into URL paths use `^[0-9]+$` with the
`GHORG_MAX_ID_LEN=20` byte cap. Length cap matters: `^[0-9]+$`
alone accepts arbitrary length.

**G-003: Sanitize API-derived strings before display sinks.**
Every value flowing into a `log` (or `printf`) for an operator-
visible message goes through `ghorg_safe_print` (which calls
`sanitize-string` from helper-scripts). Strips ANSI escapes,
control characters, HTML markup; truncates oversized payloads.

**G-004: Don't sanitize the raw API body before parsing.** The
parser (jq) is the schema validator. Sanitize after extraction,
before display.


## Resource caps

**G-010: Bounded pagination.** `GHORG_MAX_PAGES=100` caps a
hostile / runaway pager loop.

**G-011: Bounded redirects.** `GHORG_MAX_REDIRS=5` caps a curl
redirect chain. Curl strips Authorization on cross-host redirect;
this caps request-URL exfil through a long redirect chain.

**G-012: Bounded body size.** curl `--max-filesize` caps an
oversized response body at 10 MB.

**G-013: Bounded numeric ID length.** `GHORG_MAX_ID_LEN=20` (see
G-002).


## Clone-time hardening (github-org-clone)

**G-020: `GIT_LFS_SKIP_SMUDGE=1` on clone.** Blocks the LFS smudge
filter from auto-fetching attacker-chosen objects when an upstream
`.gitattributes` points binaries at LFS.

**G-021: `protocol.file.allow=never` and
`protocol.ext.allow=never` on clone.** Blocks the `file://` and
`ext::` helper protocols (historical CVE class for read-local-file
or run-shell-command via hostile-upstream redirect).


## Tool-family conventions

**G-030: Mode flag is required, no implicit default.** Every
github-org-* / dm-github-* tool requires `--apply` or `--dry-run`
(plus `--audit` where applicable). Conflicting mode flags die 64.

Why: running without a mode flag is the kind of "intent unclear"
footgun that mutates production by default if the implicit
fallback is `apply`. A required flag closes that gap.

**G-031: Use the shared parser+postlude wrapper.** Both
dm-github-policy and dm-github-personal-policy call
`policy_tool_init <expected-positional-count> "$@"`, which wraps:

- `policy_parse_mode_args` (the flag parser)
- positional-count check (caller-defined `show_help` + `die 64`)
- `mode_set` check (same)
- `ghorg_require_deps` (R-091, R-092)
- `policy_warn_seen=0` (G-032)

Caller still declares the state vars at the top:
`mode='' dry_run=0 verbose=0 mode_set=0 positional=()`. The array
init in particular is required (R-025).

**G-032: One-bit warn tracking via `policy_warn_seen`.** No per-
status counters or summary printouts. The lib's `policy_api_call`
sets `policy_warn_seen=1` on every warn (bash dynamic scoping);
the tool tests `[ "${policy_warn_seen}" -eq 1 ]` at exit and
returns 1 if set. CI / cron callers learn run success/failure
from the exit code.

Why: counts add noise without signal beyond what the log lines
already convey (the operator sees each warn at the moment it
happens). One bit is enough to decide "did anything go wrong";
which specific thing is in the visible log.

**G-033: Sequential per-repo loops, not `&` background.**
Backgrounding loses caller-scope mutations of `policy_warn_seen`
(R-052). For 1-org / ~12-repo scale the parallelism savings are
not worth the tempfile-or-pid-collection complexity.

**G-034: Pages DELETE 404 is success.** `policy_api_call` accepts
an optional 5th arg "extra ok status" (single value). The
GitHub Pages cleanup step passes `'404'` because that is the
documented "no Pages site to delete" response and not a warn.


## Mock-API tests

**G-040: Every test under `ci/tests/test_*.sh` is hermetic.**
`GHORG_MOCK=1` + `GHORG_MOCK_DIR=ci/fixtures` route every API
call to a local fixture file. No network, no real tokens.

**G-041: Capture stderr too via `2>&1`.** All user-facing output
goes through `log` (R-040) which writes to stderr. Tests that
capture only stdout get an empty string and silently fail every
substring grep.

**G-042: Don't anchor `^prefix` greps in tests against
log-prefixed output.** Use `--fixed-strings` substring matches or
exit-code checks. The log prefix (`script.sh [NOTICE]: `) sits in
front of every line; column-0 anchoring breaks after every refactor.

**G-043: Prefer exit-code-based test assertions to output-format-
based ones.** Output formats are brittle; exit codes are contract.


## Audit checklist

When the lib or tools change, scan for these. (Keep this list
short; longer rules go above.)

- New API-extracted string flowing into a URL/file/git/curl arg?
  Needs `ghorg_validate_name` (G-001) or numeric regex + length
  cap (G-002) before that sink.
- New API-extracted string flowing into a `log` for the operator?
  Needs `ghorg_safe_print` (G-003).
- New `<( ... )` process substitution feeding a `read` loop?
  Errors inside the substitution are invisible to `errexit`;
  prefer pre-capture into a `$( ... )` string, or document why
  the substitution form is intentional.
- New backgrounded `&` worker that needs to update shared state?
  Sequentialize the loop or use a tempfile + atomic appends; see
  R-052 for the underlying constraint.
- New `policy_api_call` site against an endpoint with a documented
  non-2xx success status (e.g. DELETE on a missing resource)?
  Pass that status as the 5th arg (G-034 example).
