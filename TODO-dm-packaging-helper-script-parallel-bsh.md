# TODO: drop dm_parallel_wait shim, source helper-scripts/parallel.bsh directly

## Background

`usr/libexec/developer-meta-files/parallel.bsh` is a backward-compat shim:
it sources `helper-scripts/parallel.bsh` and re-exports `parallel_wait` as
`dm_parallel_wait` (and re-fills `dm_parallel_failures` from
`parallel_failures`). The user has decided to drop the alias outright
and migrate all callers to `parallel_wait` directly.

Known callers of the shim today:

1. `usr/bin/dm-packaging-helper-script` (sources `parallel.bsh`,
   calls `dm_parallel_wait`, reads `dm_parallel_failures`)
2. `usr/bin/dm-push`                    (sources `parallel.bsh`,
   calls `dm_parallel_wait`, reads `dm_parallel_failures`)

Both must be migrated **before** the shim file can be deleted, or
the maintainer who only patches one of them will end the operation
in a state where `dm-push` (or `dm-packaging-helper-script`) fails
at startup with a missing-file source error.

Codex flagged this on developer-meta-files#1 review of the TODO
file (P1) - the original instruction said to `git rm` the shim after
patching only `dm-packaging-helper-script`, which would break
`dm-push` immediately.

## Required edits

### Per-caller patch

For each of `usr/bin/dm-packaging-helper-script` and `usr/bin/dm-push`,
apply this substitution:

```bash
sed -i \
  -e 's|packages/kicksecure/developer-meta-files/usr/libexec/developer-meta-files/parallel.bsh|packages/kicksecure/helper-scripts/usr/libexec/helper-scripts/parallel.bsh|g' \
  -e 's|/usr/libexec/developer-meta-files/parallel.bsh|/usr/libexec/helper-scripts/parallel.bsh|g' \
  -e 's|# shellcheck source=../libexec/developer-meta-files/parallel.bsh|# shellcheck source=/usr/libexec/helper-scripts/parallel.bsh|g' \
  -e 's|\bdm_parallel_wait\b|parallel_wait|g' \
  -e 's|\bdm_parallel_failures\b|parallel_failures|g' \
  usr/bin/dm-packaging-helper-script usr/bin/dm-push
```

Verify each file individually after the sed pass:

```bash
for f in usr/bin/dm-packaging-helper-script usr/bin/dm-push; do
  bash -n "$f" || { printf 'syntax error in %s\n' "$f" >&2; exit 1; }
done
grep -nE 'dm_parallel_wait|dm_parallel_failures|/libexec/developer-meta-files/parallel' \
  usr/bin/dm-packaging-helper-script usr/bin/dm-push
```

The `grep` must return zero matches. If anything is left, the next
step would silently break it.

### Only after BOTH callers are clean: delete the shim

```bash
git rm usr/libexec/developer-meta-files/parallel.bsh
```

Final verification across the whole repo (must return zero matches):

```bash
grep -nrE 'dm_parallel_wait|dm_parallel_failures|/libexec/developer-meta-files/parallel' .
```

## Why this is not auto-applied

The MCP push tools require the full file content in a single tool-call
parameter. `dm-packaging-helper-script` is ~91 KB and consistently
times out on the GitHub MCP push channel; the diff itself is trivially
small but the blocker is purely transport-size, not the change.

`dm-push` is smaller (~25 KB) and individually pushable, but I’m
holding off on it until both are migrated together so the repo is
never in a state where one is on the new shim path and the other on
the old.
