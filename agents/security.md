# Security model (AI-Assisted)

## Introduction

Two threat models cover code in this org. They have **different
trust roots and different goals**, so a property that holds for one
does not automatically hold for the other. This file documents
both and sketches when each applies; the production-code threat
model has a fuller deep dive in derivative-maker.

The split exists because:

- **CI workflows** run on github.com
  github.com is the trust root
  because github.com is the action target. There is no way to
  run CI actions while distrusting github.com.
- **release artifacts**
  The release's integrity must be independent of github.com.
  github.com is a transport, not a trust root; only Sequoia (`sq`)
  digital software signatures over upstream tags count.

The rest of this file develops both threat models, then lists the
shared code conventions (untrusted-input handling, things we don't
carry in-tree).

## Threat model A: CI workflows

**Scope:**

- `.github/workflows/*.yml` + their `ci/*.sh` runners - run **only**
  in GitHub Actions, never from a maintainer machine.

(Maintainers do not run CI scripts locally.)

**Trusted (out of scope):**

- **github.com itself.** Malicious code shipped through github.com,
  compromised git serving infrastructure, force-pushes / roll-back
  attacks on public repos we depend on (`Kicksecure/helper-scripts`,
  `Kicksecure/genmkfile`). We pin to a branch (`master`), not a
  commit SHA. Adding workflow vars and SHA-pin ceremony around
  every helper-scripts pull would be heavy ceremony for a threat
  we do not model. CI runs on github.com; if github.com is
  compromised, the CI itself is compromised.

- **`PATH`.** `command -v <helper>` is a first-hit lookup against
  the operator's `PATH`. If `PATH` has been hijacked to shadow
  these binaries, the script cannot recover; PATH integrity is an
  operator responsibility.

- **Authentication tokens.** Tokens are treated as a *secret to
  protect* (xtrace suppression, no argv leak via curl `--config`)
  but their content is *trusted as authentic*. A short cheap
  format check (length cap, `^[A-Za-z0-9_]+$`) so a token file
  accidentally containing a comment or trailing quote fails closed
  instead of corrupting downstream config; we do **not** treat the
  token as hostile data.

- **The CI's local filesystem.** `/tmp`, `${HOME}/.config`,
  the source tree itself. If an attacker can write to those, they
  can already run arbitrary code as the operator and the script
  cannot defend.

**Untrusted (in scope):**

API response bytes from github.com (the JSON we parse) are treated
as hostile data. See "Code conventions" below.

## Threat model B: production code

**Scope:** the build that produces release artifacts.

**Trusted:** Sequoia (`sq`) signatures over upstream Git tags.
The maintainer's local filesystem at the moment `derivative-update`
runs (i.e. the operator is expected to have verified repo integrity
out-of-band before invoking).

**Untrusted:** everything pulled from github.com. `git checkout`
does NOT execute against a fetched ref until that ref has been
cryptographically verified by `help-steps/git_sanity_test`. github.com
and the git transport are *explicitly distrusted*; only the signed
tag is trusted.

This file does not enumerate the production-code rules; for that
side, see:

* [`derivative-maker/agents/security.md`](https://github.com/Kicksecure/derivative-maker/blob/master/agents/security.md)
* [`derivative-maker/agents/git_sanity_test_security.md`](https://github.com/Kicksecure/derivative-maker/blob/master/agents/git_sanity_test_security.md).

## Comparison at a glance

| Property | A: CI / maintenance tooling | B: production code |
|---|---|---|
| Where it runs | GitHub Actions (workflows) | maintainer machine (build) |
| Goal | CI testing | produce signed release artifacts |
| Trust root | github.com (the action target) | Sequoia (`sq`) signed tags |
| github.com | trusted | NOT trusted (transport only) |
| git transport | trusted | NOT trusted |
| Branch vs SHA pin | branch (`master`) is fine | n/a (signed tag, not branch) |
| Untrusted bytes | remote servers | upstream git refs (until verified), remote servers |
| Verification before checkout | optional | required |
| Local filesystem | trusted | trusted (verified out-of-band) |
| `PATH` | trusted | trusted |

## API-derived strings are untrusted

Treat every byte returned by an external service as untrusted. Two
enforcement points:

1. **Identifier sinks** - URL paths, file paths, command-line
   arguments, git arguments. Pass through a strict allowlist
   validator (e.g. `^[A-Za-z0-9._-]+$` for names, `^[0-9]+$` with
   a length cap for numeric IDs) before use.

2. **Display sinks** - anything that flows into a `printf` for an
   operator-visible message. Pass through a sanitizer (e.g.
   `sanitize-string` from helper-scripts) that strips ANSI escapes,
   control characters, HTML markup, and truncates oversized
   payloads.

Bound the local damage a hostile or misbehaving server can cause
through pagination, redirect chains, or oversized bodies via
per-tool caps (max pages, max redirects, max body size, max ID
length).

## Parser-level trust assumptions

The "API bytes are untrusted" rule above governs the LOGIC of how
parsed values are used. It does NOT mitigate memory-safety bugs in
the parser ITSELF. Every script in this org makes implicit trust
assumptions about its parsing tools:

- **`jq`** (C). Trusted to parse hostile JSON without overflowing.
- **`curl`** (C). Trusted to handle hostile HTTP responses.
- **bash**

## What we do not carry in the source tree

- **Speculative / aspirational security findings** ("if X ever
  publishes a stable Y, we could call it"). Belongs in a follow-up
  issue, not a TODO comment with a sample body block.
- **CI tests proving a one-line fix works.** Code review catches
  "missing value for --include exits 64"; a dedicated
  `test_missing_option_value_rejected.sh` does not pay for itself.
- **Tests that mock binaries via shell function override** (e.g.
  `stat() { return 1; }` to fake a stat failure). They are fragile
  (defeated by `command stat` or absolute-path invocations), and
  prove only that the mock fires, not that real-binary failure is
  handled. Fix the underlying production code path so it fails
  closed; rely on review to confirm.

## Conclusion

Don't
copy assumptions from one model into the other - especially: never
add SHA-pin ceremony to threat-model-A code on the basis that
"production code does it"; never accept a branch pin in
threat-model-B code on the basis that "CI tooling does it." The
trust roots are different, so the right answer is different.

In doubt, ask.
