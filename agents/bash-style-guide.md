# Bash Style Guide (AI-Assisted)

Bash style for assisted-by-ai org scripts. Rules are flat-numbered
(R-NNN) so they can be cited in code review, commit messages, and
PR replies. Project-specific rules for the github-org-* / dm-*
surface live in [github-org-tools.md](github-org-tools.md) under
G-NNN.

Each rule: a one-line statement (the bold first sentence), an
optional "Why" rationale, an optional code example. Skim the bold
lines to audit a diff; read the Why for context. Rules at the top
of a section are hard; rules at the bottom are softer preferences.

Hard rules at the top, soft preferences at the bottom of each
section. Rules that cite a helper script include the source path
so a reader can confirm intent against implementation.


## File-level

**R-001: ASCII only.** Source code and commit messages are ASCII
only. No smart quotes, em dashes, zero-width spaces, emoji.

Why: AI tools reflexively render bullet lists with cosmetic
unicode (U+2014 em dash, U+2192 right-arrow); strip them. ASCII-
only files make `LC_ALL=C grep -PlI '[^\x00-\x7F]'` a useful
pre-push gate. The runnable gate
[`agents/pre-push-static.sh`](pre-push-static.sh) applies that
grep to both changed files and the commit-range message; install
it as `.git/hooks/pre-push` to make R-001 violations impossible
to push.

**R-002: File header includes the 'AI-Assisted' marker.** Every
new file from scratch carries the standard 5-line header:

    #!/bin/bash

    ## Copyright (C) 2026 - 2026 ENCRYPTED SUPPORT LLC <adrelanos@whonix.org>
    ## See the file COPYING for copying conditions.

    ## AI-Assisted

    ## <one-line description of what the script does>

Why: marks AI involvement; satisfies the project's attribution
policy.


## Shell options

**R-010: Set the strict-mode quintet at the top of every script.**

    set -o errexit
    set -o nounset
    set -o pipefail
    set -o errtrace
    shopt -s inherit_errexit
    shopt -s shift_verbose

Why: `errexit` aborts on first uncaught failure. `nounset` catches
unset-variable typos. `pipefail` makes the exit code of a pipeline
the first non-zero (so failures earlier in the pipe propagate).
`errtrace` makes ERR traps inherit into shell functions and command
substitutions. `inherit_errexit` makes `$()` subshells respect
errexit (bash >= 4.4). `shift_verbose` logs when `shift` runs past
argv end.

**R-011: Don't toggle errexit around a command to capture its rc.**
Use `||`-suffixed assignment.

Bad:

    set +o errexit
    out="$(cmd)"
    rc=$?
    set -o errexit

Good:

    rc=0
    out="$(cmd)" || rc=$?

Why: shorter, errexit-on-by-default never lapses, `inherit_errexit`-
safe.


**R-012: Arithmetic assignment uses `var=$((expr))`, never
`(( expr ))`.** Under `errexit`, an arithmetic expression that
evaluates to zero exits the shell.

Bad:

    (( count += 1 ))            # if count was 0, now (( 1 )) -> ok
    (( found = 0 ))             # exits the script (rc=1)

Good:

    count=$((count + 1))
    found=0

Why: `(( expr ))` returns rc=1 when `expr` evaluates to 0 (POSIX
arithmetic-expression semantics), which `errexit` interprets as a
command failure. `var=$((expr))` is an assignment - rc is always
the assignment's rc (0), not the computed value.


## Variables

**R-020: Wrap every variable reference in `${var}` braces.** No
bare `$var`.

Why: removes shell-parser ambiguity at concatenation boundaries
(`${prefix}foo` vs `$prefixfoo`); makes refactor regex-greppable;
matches what shellcheck would flag in pedantic mode.

**R-021: Declare locals at the top of the function, blank line,
then assignments.**

    foo() {
       local repo url current_branch

       repo="$1"
       url="$(remote_url "${repo}")"
    }

Why: separates declaration from assignment; one place to audit
"what state does this function have"; matches the codebase norm.

**R-022: Don't combine `local` with command-substitution
assignment.** `local x="$(cmd)"` masks the substitution's exit
status (the `local` builtin returns 0 even when `$(cmd)` failed),
so errexit cannot fire. Split into two statements.

Bad: `local out="$(cmd)"`

Good:

    local out
    out="$(cmd)"

**R-023: Variable names are descriptive.** No single-letter (`e`,
`x`, `t`) or cryptic abbreviations (`tmpfn`, `cfg2`).

**R-024: Variable names in error messages are wrapped in single
quotes.** `log error "couldn't read '${path}'"`.

Why: single quotes make trailing/leading whitespace in the
expanded value visible (otherwise lost in line-break artifacts).

**R-025: Arrays touched under `nounset` must be `arr=()`-
initialized before any access.**

Why: `${#arr[@]}` and `"${arr[@]}"` raise `arr: unbound variable`
when the array has never been assigned. The first `arr+=(item)`
auto-creates, but that does not help paths where no items are
appended (e.g., a parser that sees no positional args).


## printf

**R-030: Always `printf '%s\n' "..."`.** Format string is fixed;
all data goes in the data string. No `%d`, no `%q` (except where
shell-escaping is genuinely required), no extra `\n` in the format.

**R-031: Multi-line block: ONE quoted string with embedded
newlines.** Multiple separate lines: one `printf '%s\n'` per line.
Blank line: `printf '%s\n' ""`, NOT `\n` in the format.

**R-032: Quote choice.** Double quotes preferred. Single quotes
acceptable when the body has many doubles to escape:

    printf '%s\n' '"has" "a" "lot" "quotes"'

**R-033: Don't inline `$(cmd)` in a printf format string.** Pre-
compute into a named variable.

Bad:  `printf '%s\n' "warn: $(my_helper "${value}")"`

Good:

    result="$(my_helper "${value}")"
    printf '%s\n' "warn: ${result}"


## printf vs log

**R-040: Output to user goes through `log`, not bare printf.**
Every line written to the operator's terminal uses `log notice` /
`log warn` / `log error` (helpers from
`helper-scripts/log_run_die.sh`). The helpers prefix with the
script name and a level tag (`script.sh [NOTICE]: ...`).

Why: the operator gets context for each line - which tool is
talking and at what severity. Bare `printf '%s\n'` to stdout/
stderr loses both. Tests that grep substrings inside the line
still match because the log helper preserves the body verbatim
after the prefix.

**R-041: Reserve `printf` for cases where it is genuinely the
right tool.**

- writing to a file or pipe: `printf '%s\n' "${name}" >> "${file}"`
- feeding a value through a subshell to another tool:
  `names="$(printf '%s' "${body}" | jq -r '.[].name')"`
- building strings via `printf -v`

**R-042: Drop blank-line separators (`printf '%s\n' ""` /
`log notice ""`).** Once every line carries a `[NOTICE]:` prefix,
blank lines are noise.


## Functions

**R-050: A function definition's closing `}` is followed by
exactly one blank line.** End-of-file is the only exception.

    foo() {
       local x

       x="$1"
    }

    bar() {
       ...
    }

Why: without a blank line the next block runs into the function
body visually and the boundary is hard to spot in a 600-line file.

**R-051: Trap targets are standalone named functions, never inline
command strings.**

    foo_cleanup_tmp() {
       safe-rm --force -- "${tmp_file}"
    }

    foo() {
       local tmp_file

       tmp_file="$(mktemp)"
       trap foo_cleanup_tmp RETURN
    }

Why: the trap function references variables from the calling
scope via dynamic scoping; registering AFTER vars are initialized
means the reference is `nounset`-safe with no `${var:-}` default.

**R-052: Backgrounded children (`&`) cannot mutate the parent
shell's variables.** If a per-item loop with `&` needs shared
state (a counter, a flag), use a tempfile with PIPE_BUF-atomic
appends or sequentialize the loop.

Why: child shells get a copy of the parent's vars; assignments
inside the child are lost on `wait`. Single-byte appends to a
file (`printf 'w' >> "${flag}"`) are atomic across concurrent
writers up to PIPE_BUF (4096 bytes on Linux).


## Flags

**R-060: Long flag names whenever the tool supports one.**
`--quiet`, `--ignore-case`, `--lines=1`, `--unique`,
`wc --lines`, `sort --unique`.

Why: long flags self-document; survive being copy-pasted into a
context without `man <tool>` open; reviewers don't need to recall
short-flag meanings.

**R-061: Split combined short flags.** `rm -rf` -> `rm -r -f`,
`declare -gA` -> `declare -g -A`.

**R-062: Use `--` end-of-options separator wherever the tool
supports one and positional args follow.** Verified working in:
`git`, `grep`, `sed`, `tr`, `jq`, `head`, `tail`, `stat`,
`mktemp`, `wc`, `sort`, `cat`, `rm`, `safe-rm`, `mkdir`, `find`.
Verify before extending the list.

Why: a positional that begins with `-` (legitimate or hostile)
gets treated as a flag without `--`. NB: `git check-ref-format`
does NOT support `--`; verify against the actual binary before
adding `--` to a new tool invocation.


## Case statements

**R-070: `;;` on its own line, never trailing the last
statement.**

**R-071: One statement per line in a case arm.** Multi-statement
single-line arms get split.

**R-072: Reserved-name and metachar-looking literals are quoted.**
`'.git'` not `.git`, `'-'*` not `-*`.

**R-073: Quote interpolated values in case patterns: `"${x}"`,
not `${x}`.** Bash treats unquoted expansions in case patterns
as glob, with NO `|`-alternation interpretation across the
expansion. Single-value semantics only.

Why: shellcheck SC2254 fires on the unquoted form. The quoted
form makes the interpolation a literal pattern. If you need
multi-value alternation, build the case manually rather than
expanding a `|`-separated string.

    case "${kind}" in
       repo)
          max_len="${MAX_REPO}"
          ;;
       user)
          max_len="${MAX_USER}"
          ;;
    esac


## Sourcing helper-scripts

**R-080: `# shellcheck source=<real install path>` directive
above each source line, paired with a `${HELPER_SCRIPTS_PATH:-}`
prefix on the actual source.**

    # shellcheck source=/usr/libexec/helper-scripts/<file>
    source "${HELPER_SCRIPTS_PATH:-}"/usr/libexec/helper-scripts/<file>

Why: the empty `${HELPER_SCRIPTS_PATH}` resolves to the system
install at `/usr/libexec/helper-scripts/`; a caller running with
helper-scripts as a submodule sets the var to the submodule path.
shellcheck doesn't expand the prefix at lint time but the
`source=` directive points it at the absolute path that exists in
CI.

**R-081: Never fall back to `source=/dev/null`.** That silences
cross-file checks.

**R-082: Each consumer sources every helper-scripts file it uses
directly.** Don't rely on transitive sourcing.

Why: `log_run_die.sh` happens to source `strings.bsh` for its own
use; if your script also calls `is_whole_number`, source
`strings.bsh` itself. Otherwise a future refactor that drops the
transitive source breaks you silently.

**R-083: `wc` invocations are preceded by sourcing
`wc-test.sh`.**

Why: a broken `wc` binary fails loudly rather than silently
producing an empty count.

**R-084: Reuse strings.bsh helpers before reimplementing.**
`is_whole_number`, `validate_safe_filename`,
`check_is_alpha_numeric`, etc.


## Command availability checks

**R-090: `has` from `helper-scripts/has.sh`, not
`command -v X >/dev/null 2>&1`.**

    # shellcheck source=/usr/libexec/helper-scripts/has.sh
    source "${HELPER_SCRIPTS_PATH:-}"/usr/libexec/helper-scripts/has.sh

    has github-org-fork \
       || die 1 "'github-org-fork' not on PATH"

Why: `has` verifies the result is executable and guards against
aliases/functions; `command -v` matches any of those.

**R-091: Pre-flight checks at the top, not scattered.** A tool's
runtime command dependencies are checked once, near the top of
the script's setup phase, not lazily inside the function that
happens to need each one.

Why: lazy checks fail halfway through a per-repo loop and leave
partial state behind; a top-of-file pre-flight bails before any
mutation runs.

**R-092: Where a family of tools shares the same deps, the lib
provides a single helper.**

    ghorg_require_deps    ## base set, including git

Don't add an inline `has git || die ...` at the per-feature site
when the shared pre-flight already covers it.

**R-093: Exception for `.github/actions/install-deps/install-helper-scripts.sh`.**
That script runs BEFORE helper-scripts is installed, so it falls
back to plain `command -v`. The same exception applies to
`agents/pre-push-static.sh`, which must run as a bare git hook
without sourcing helper-scripts.


## Workflow scripts

**R-100: Substantial bash logic does not belong inside a workflow
YAML's `run: |` block.** If the step is more than ~5 lines (or
has any control flow, retry loop, polling, error handler), put it
in a standalone script under `ci/` and have the workflow call it.

    - name: Start systemd-enabled Debian container
      run: ./ci/dry-run-start-container.sh dryrun "${DEBIAN_IMAGE}"

Why: shellcheck only sees real `.sh` files, not YAML blocks;
inline shell silently bypasses linting. A standalone script is
reproducible from a developer machine. Diff reviews are line-
level instead of YAML-indent-embedded. The script's args are an
explicit, named, testable contract.

**R-101: Workflow YAML and its scripts share a prefix.**

    .github/workflows/dry-run.yml
                      ^  (same prefix)
                      v
    ci/dry-run-derivative-maker.sh

Why: a reader scanning either folder finds the matching
counterpart at a glance.

**R-102: Don't prepend the interpreter when the shebang suffices.**
A script with a `#!/bin/bash` shebang and executable bit, invoked
as `path/script.sh`, runs under its declared interpreter. Adding
an explicit `bash` (or worse, `sh`) prefix is redundant or
actively wrong.

Bad:

    bash build.sh
    sh ci/foo.sh
    bash ci/dry-run-start-container.sh ...

Good:

    ./build.sh
    ci/foo.sh
    ./ci/dry-run-start-container.sh ...

Why: `sh script.sh` runs the script under /bin/sh, NOT bash,
regardless of the shebang line. Bash-specific syntax (arrays,
`[[ ]]`, `local`, `set -o pipefail`) silently breaks or behaves
weirdly. `bash script.sh` is merely redundant when the shebang
already says bash, but it also defeats the contract -- the
shebang declares the interpreter; the invoker shouldn't override
it. Applies to CI YAML `run:` blocks, Makefile recipes, wrapper
scripts, and ad-hoc invocations.

Exception: bootstrap that runs before the executable bit is set
(fresh `git clone` with `core.fileMode=false`, or a tarball that
lost +x), or surfaces that don't honor the shebang. State the
reason inline.


## Errors and logging

**R-110: Use `log` and `die` from `helper-scripts/log_run_die.sh`,
not ad-hoc `printf >&2; exit N`.**

    log error "couldn't read '${path}'"   ## log only
    log warn  "..."
    log notice  "..."
    log info  "..."
    die 1 "fatal: ..."                     ## logs error then exit 1
    [ "$#" -ge 2 ] || die 64 "missing value for --include"

Why: `die <code> <msg>` is the one-liner for "log error then
exit." Inside a function that should return rather than exit, use
`log error "..."; return N`.


## File deletion

**R-120: `safe-rm`, not `rm`.** Long-flag form: `safe-rm --force --`
or `safe-rm --recursive --force --`.

Why: `safe-rm` consults a blocklist before deleting (paths like
`/`, `/usr`, `~`).


## Null command

**R-130: `true` instead of `:` for no-op placeholders.** Pass a
descriptive message so xtrace logs convey intent:

    true "INFO: ghorg_api: HTTP 429 - will retry"

**R-131: Bare `true > "${file}"` is fine for "truncate file".
`while true` is fine for an infinite loop.**


## Untrusted external data

**R-140: Treat every byte returned by an external service as
untrusted.**

- **Identifier sinks** (URL paths, file paths, command-line
  arguments): pass through a strict allowlist validator (e.g.
  `^[A-Za-z0-9._-]+$`) or a numeric-only regex with length cap
  before use.
- **Display sinks** (printf/log to stdout/stderr): pass through a
  sanitizer (e.g. `sanitize-string`) that strips ANSI escapes,
  control chars, HTML markup, and truncates oversized payloads.
- **Don't sanitize the raw API body before parsing** - the parser
  (jq) is the schema validator. Sanitize after extraction, before
  display.

Why: the validator enforces what the consumer actually accepts;
the sanitizer enforces what's safe to render to a terminal. Both
are needed; one doesn't substitute for the other.

The github-org-* / dm-* tools implement R-140 via
`ghorg_validate_name` and `ghorg_safe_print`; see
[github-org-tools.md](github-org-tools.md) G-001 through G-004
for the project-specific implementation.


## Comments

**R-150: State rationale once per file.** Don't copy-paste a
multi-line `Why` block to multiple sites; at subsequent sites,
drop the comment or use a one-liner referencing a rule ID
(`R-NNN`, `G-A-NNN`, `W-NNN`).

Why: copy-pasted rationale rots - site N+1 drifts from site 1
over time; readers stop trusting all of them. Single source of
truth survives. Applies to any source file the org maintains
(bash, YAML, python, markdown).


**R-151: Comment when the code couldn't express the intent.** A
comment is an admission the code failed to express itself; prefer
renaming, extracting, or restructuring first. When unavoidable,
reserve comments for hidden constraints, subtle invariants, bug
workarounds, surprising side effects. Don't restate WHAT (well-
named identifiers do that). Bad: `## initialize i with 0` over
`i=0`.

Why: obvious comments dilute attention from the ones that matter;
reviewers learn to skim past them and miss the rare comment
documenting a real gotcha. Be concise: if removing the comment
wouldn't confuse a future reader, don't write it.


**R-152: Match the file's existing comment style.** Before
adding comments to an existing file, read the comments already
there - density, tone, idiom, voice - and match them. Don't
impose your preferred style on a file someone else established
(unless an explicit rule above says you must).

Why: file-local consistency keeps each file readable as a unified
document; jarring shifts in voice signal copy-paste and undermine
trust in the prose. Match locally; impose org-wide style only
when it would otherwise conflict.
