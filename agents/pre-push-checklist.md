# Pre-push checklist (AI-Assisted)

Skim before every push.

* Scope: any change to bash script, or `agents/`.
* Bash style: [agents/bash-style-guide.md](bash-style-guide.md).
* Project-specific rules: [agents/github-org-tools.md](github-org-tools.md).

The list is grouped by phase. Skip items that don't apply to your
diff; don't skip a phase. Each item cites the relevant rule.

## Static checks

    [ ] bash -n on every changed script
    [ ] shellcheck --external-sources (-x) on the same set
        (catches SC2317 unreachable-via-source for callbacks
        invoked indirectly across files)
    [ ] LC_ALL=C grep -PlI '[^\x00-\x7F]' on changed files
        (R-001 ASCII only)
    [ ] LC_ALL=C grep -P '[^\x00-\x7F]' on the commit message
        (R-001 ASCII only)

## Style spot-check (touched code only)

    [ ] ${var} braces, no bare $var (R-020)
    [ ] local var1 var2 var3 at top of function, blank line,
        then assigns (R-021)
    [ ] no 'local x="$(cmd)"' (R-022; masks failure)
    [ ] arr=() initialized before any access under nounset (R-025)
    [ ] long flags where supported (R-060)
    [ ] '--' end-of-options on tools that accept it (R-062;
        verified against the actual binary before adding)
    [ ] case ;; on its own line; reserved patterns quoted (R-070,
        R-072)
    [ ] case-pattern interpolations quoted: "${x}" not ${x}
        (R-073; SC2254)
    [ ] # shellcheck source=<real path>, never /dev/null (R-080,
        R-081)
    [ ] log/die from log_run_die.sh, not ad-hoc 'printf %s\n
        "error: ..." >&2' (R-040, R-110)
    [ ] has from has.sh, not 'command -v X >/dev/null 2>&1'
        (R-090)
    [ ] safe-rm, not rm (R-120)
    [ ] traps as named functions, registered after vars init
        (R-051)
    [ ] true "INFO: ..." not bare ':' (R-130)
    [ ] no $(cmd) inside printf format strings; hoist to a named
        variable (R-033)
    [ ] blank line after function closing brace (R-050)
    [ ] errexit not toggled around capture; use 'rc=0; out=$(cmd)
        || rc=$?' (R-011)

## External invocations

    [ ] Any new external command / new flag -> run it locally
        first with the actual argv being constructed
        (e.g., 'git check-ref-format refs/heads/main' BEFORE
        pushing; --branch / -- variants of git check-ref-format
        return rc=129 even on valid input)
    [ ] If the command is sensitive to flags vs. positional,
        test both legitimate and adversarial inputs
        ('-foo', '..', empty)
    [ ] If a docstring claims a parameter accepts a particular
        form (e.g., '404|409' alternation), parametrically
        verify the bash construct supports it. Bash case-pattern
        expansion does NOT interpret '|' as alternation across
        an interpolated value (R-073).

## Refactor-aware re-check

    [ ] After ANY refactor that changes function scope, signature,
        or boundary: re-trace data flow end-to-end. (Footgun:
        dropped 'positional=()' init when collapsing a parser
        block; the test only failed under nounset + missing-arg
        path, not the happy path.)
    [ ] After ANY printf->log conversion: re-check tests that
        anchor on '^' prefix or rely on stdout-only capture.
    [ ] After dropping a flag's parallelism / backgrounding:
        verify the new sequential code-path actually reaches
        every item (not just compiles).

## Commit

    [ ] Every new file from scratch has 'AI-Assisted' marker
        (R-002)
    [ ] No emoji, no smart quotes, no em dashes in commit message
        (R-001)
