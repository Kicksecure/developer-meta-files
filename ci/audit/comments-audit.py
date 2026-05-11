#!/usr/bin/python3

"""Heuristic comment auditor for R-151 violations.

Walks .sh / .bash / .bsh / .py / .yml / .yaml files and flags
comment-immediately-before-code pairs where the comment is
probably paraphrasing the code rather than documenting a non-
obvious why.

This is FUZZY. The output is a candidate list a human reviews,
not a pass/fail gate.

Heuristic categories the script emits:

  R151-PARAPHRASE   single-line comment whose content overlaps
                    heavily with the next non-blank code line
                    (set / set X to Y, install <pkg>, return X,
                    exit N, ...)

  R151-MARKER       trivial end-marker / structure comments like
                    '# end of <X>', '# fi', '# close <X>'

  R151-RESTATE      comment uses the same identifier as the code
                    line below AND the comment is short (<= 6
                    tokens) AND the verb is from a fixed
                    'restate' list (set, get, init, declare,
                    install, return, exit, print, echo, loop,
                    iterate, check, define, create).

Usage:  python3 comments-audit.py <repo_root>
Exits:  always 0 - this is an audit, not a gate.
"""

import os
import re
import sys


COMMENT_LINE = {
    ".sh":   re.compile(r"^\s*##?\s*(.*)$"),
    ".bash": re.compile(r"^\s*##?\s*(.*)$"),
    ".bsh":  re.compile(r"^\s*##?\s*(.*)$"),
    ".py":   re.compile(r"^\s*##?\s*(.*)$"),
    ".yml":  re.compile(r"^\s*##?\s*(.*)$"),
    ".yaml": re.compile(r"^\s*##?\s*(.*)$"),
}

RESTATE_VERBS = {
    "set", "get", "init", "initialize", "declare", "install", "return",
    "exit", "print", "echo", "loop", "iterate", "check", "define",
    "create", "make", "build", "run", "call", "assign", "increment",
    "decrement", "add", "remove", "delete", "open", "close", "read",
    "write", "load", "save", "find", "search", "grep", "filter",
    "match", "parse", "decode", "encode", "fetch", "download",
    "upload",
}

MARKER_PATTERNS = [
    re.compile(r"^end of\b", re.I),
    re.compile(r"^fi\b", re.I),
    re.compile(r"^done\b", re.I),
    re.compile(r"^esac\b", re.I),
    re.compile(r"^close\b", re.I),
    re.compile(r"^closing\b", re.I),
    re.compile(r"^begin\b", re.I),
    re.compile(r"^start of\b", re.I),
]

## File-header / banner-line allowlist - these comment lines are
## structural metadata, not commentary. Skip them.
HEADER_OK = re.compile(
    r"^(copyright\b|see the file\b|ai-assisted\b|"
    r"shellcheck\b|noqa\b|type:\s*ignore\b|"
    r"#!/|coding:|coding=)",
    re.I,
)


def normalize(s):
    """Lowercase, strip punctuation, collapse whitespace."""
    s = re.sub(r"[^\w\s]", " ", s.lower())
    s = re.sub(r"\s+", " ", s).strip()
    return s


def tokens(s):
    return normalize(s).split()


def is_restate(comment_text, code_line):
    """Return True if `comment_text` looks like a restate of `code_line`."""
    c_tokens = tokens(comment_text)
    if not c_tokens:
        return False
    if len(c_tokens) > 8:  ## long comments are likely real prose
        return False
    if c_tokens[0] not in RESTATE_VERBS:
        return False

    ## Pull identifiers from the code line.
    code_idents = set(re.findall(r"[A-Za-z_][A-Za-z0-9_]*", code_line))
    code_idents_lower = {x.lower() for x in code_idents}
    c_set = set(c_tokens)

    ## Restate: comment shares at least one non-verb token with the code.
    overlap = (c_set & code_idents_lower) - RESTATE_VERBS
    return bool(overlap)


def is_marker(comment_text):
    for p in MARKER_PATTERNS:
        if p.match(comment_text.strip()):
            return True
    return False


def is_paraphrase(comment_text, code_line):
    """
    Token-overlap heuristic. Comment is a paraphrase if:
    - both are short (<=12 tokens each), AND
    - >=50% of comment's non-stopword tokens appear in the code's
      identifiers / keywords.
    """
    c_tokens = tokens(comment_text)
    if not c_tokens or len(c_tokens) > 12:
        return False
    code_norm = normalize(code_line)
    code_tokens = set(code_norm.split())
    if not code_tokens:
        return False

    stop = {"the", "a", "an", "to", "of", "is", "are", "and", "or", "for", "in", "on", "with", "by"}
    content_tokens = [t for t in c_tokens if t not in stop]
    if len(content_tokens) < 2:
        return False
    overlap = sum(1 for t in content_tokens if t in code_tokens)
    return overlap >= max(2, len(content_tokens) // 2)


def is_skip_path(path):
    parts = path.split(os.sep)
    skip_dirs = {".git", "node_modules", "fixtures", "tests", "_temp"}
    return any(p in skip_dirs for p in parts)


def audit_file(path, findings):
    try:
        with open(path) as f:
            lines = f.readlines()
    except (OSError, UnicodeDecodeError):
        return

    ext = os.path.splitext(path)[1].lower()
    comment_re = COMMENT_LINE.get(ext)
    if not comment_re:
        return

    for i, raw in enumerate(lines):
        line = raw.rstrip("\n")
        m = comment_re.match(line)
        if not m:
            continue
        text = m.group(1).strip()
        if not text:
            continue
        if HEADER_OK.match(text):
            continue
        if text.startswith("---"):
            continue

        ## Next non-blank line - the code below the comment.
        next_code = None
        for j in range(i + 1, min(i + 4, len(lines))):
            stripped = lines[j].strip()
            if not stripped:
                continue
            if comment_re.match(lines[j]):
                continue  ## another comment - not the code yet
            next_code = lines[j].rstrip("\n")
            break
        if not next_code:
            continue

        ## Apply heuristics in order. First match wins.
        if is_marker(text):
            findings.append((path, i + 1, "R151-MARKER", text, next_code.strip()))
            continue
        if is_restate(text, next_code):
            findings.append((path, i + 1, "R151-RESTATE", text, next_code.strip()))
            continue
        if is_paraphrase(text, next_code):
            findings.append((path, i + 1, "R151-PARAPHRASE", text, next_code.strip()))
            continue


def walk(repo_root):
    findings = []
    for dirpath, dirnames, filenames in os.walk(repo_root):
        ## Prune skip-dirs in-place so we don't descend into them.
        dirnames[:] = [d for d in dirnames if d not in
                       (".git", "node_modules", "fixtures")]
        for name in filenames:
            full = os.path.join(dirpath, name)
            audit_file(full, findings)
    return findings


def main(repo_root):
    findings = walk(repo_root)
    if not findings:
        print(f"comments audit: 0 candidate findings under {repo_root}")
        return 0
    print(f"comments audit: {len(findings)} candidate finding(s) (review manually; heuristic):")
    print("----")
    by_rule = {}
    for path, line, rule, text, code in findings:
        by_rule.setdefault(rule, []).append((path, line, text, code))
    for rule, items in sorted(by_rule.items()):
        print(f"\n## {rule} ({len(items)})")
        for path, line, text, code in items[:40]:
            rel = os.path.relpath(path, repo_root)
            print(f"  {rel}:{line}")
            print(f"    comment: {text}")
            print(f"    code:    {code[:80]}")
        if len(items) > 40:
            print(f"  ... ({len(items) - 40} more)")
    return 0


if __name__ == "__main__":
    if len(sys.argv) != 2:
        print("usage: comments-audit.py <repo_root>", file=sys.stderr)
        sys.exit(2)
    sys.exit(main(sys.argv[1]))
