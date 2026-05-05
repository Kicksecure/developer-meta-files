# TODO: drop dm_parallel_wait shim, source helper-scripts/parallel.bsh directly

## Background

`usr/libexec/developer-meta-files/parallel.bsh` is a backward-compat shim:
it sources `helper-scripts/parallel.bsh` and re-exports `parallel_wait` as
`dm_parallel_wait`. The user has decided to drop the alias outright and
migrate the one caller to `parallel_wait` directly.

## Required edits to `usr/bin/dm-packaging-helper-script`

Unified diff (5 lines, 2 hunks). Apply on top of the current claude/read-agents-meta-file-uKeT9 head:

```diff
--- a/usr/bin/dm-packaging-helper-script
+++ b/usr/bin/dm-packaging-helper-script
@@ -38,9 +38,9 @@
 
 ## Reusable wait-for-pids helper. Prefer the in-tree copy when run
 ## from the source folder so dev iteration does not need a reinstall.
-parallel_helper="${derivative_maker_source_code_dir}/packages/kicksecure/developer-meta-files/usr/libexec/developer-meta-files/parallel.bsh"
-test -r "$parallel_helper" || parallel_helper="/usr/libexec/developer-meta-files/parallel.bsh"
-# shellcheck source=../libexec/developer-meta-files/parallel.bsh
+parallel_helper="${derivative_maker_source_code_dir}/packages/kicksecure/helper-scripts/usr/libexec/helper-scripts/parallel.bsh"
+test -r "$parallel_helper" || parallel_helper="/usr/libexec/helper-scripts/parallel.bsh"
+# shellcheck source=/usr/libexec/helper-scripts/parallel.bsh
 source "$parallel_helper"
 
 ## BEGIN Initialization functions {
@@ -2252,9 +2252,9 @@
 ## BEGIN Post-run hooks {
 
 wait_for_git_processes() {
-   if ! dm_parallel_wait git_pid_label ; then
+   if ! parallel_wait git_pid_label ; then
       printf '%s\n' "${red}${bold}ERROR ${BASH_SOURCE[0]}: failed git background jobs:${reset}" >&2
-      printf '   - %s\n' "${dm_parallel_failures[@]}" >&2
+      printf '   - %s\n' "${parallel_failures[@]}" >&2
       exit 1
    fi
 }
```

Or, equivalently, run this from the repo root:

```bash
sed -i \
  -e 's|packages/kicksecure/developer-meta-files/usr/libexec/developer-meta-files/parallel.bsh|packages/kicksecure/helper-scripts/usr/libexec/helper-scripts/parallel.bsh|g' \
  -e 's|/usr/libexec/developer-meta-files/parallel.bsh|/usr/libexec/helper-scripts/parallel.bsh|g' \
  -e 's|# shellcheck source=../libexec/developer-meta-files/parallel.bsh|# shellcheck source=/usr/libexec/helper-scripts/parallel.bsh|g' \
  -e 's|\bdm_parallel_wait\b|parallel_wait|g' \
  -e 's|\bdm_parallel_failures\b|parallel_failures|g' \
  usr/bin/dm-packaging-helper-script
```

## After the diff lands

Delete the now-orphaned shim:

```bash
git rm usr/libexec/developer-meta-files/parallel.bsh
```

Verify nothing else still references the old paths or names:

```bash
grep -nrE 'dm_parallel_wait|dm_parallel_failures|/libexec/developer-meta-files/parallel' .
```

Expected: zero matches.

## Why this is not auto-applied

The MCP push tools require the full file content in a single tool-call
parameter. `dm-packaging-helper-script` is ~91 KB, which consistently
times out on the push channel (4 attempts via 3 different sub-agents,
all hit `Stream idle timeout`). The diff itself is trivially small; the
blocker is purely transport-size, not anything about the change.
