# CLAUDE.md

1. Read [AGENTS.md](AGENTS.md) first. It's a 25-line index;
   skim it, then open the file relevant to the current task.
2. Before pushing, run the static-checks gate:

       agents/pre-push-static.sh origin/master

   Or install it once and forget:

       ln -s ../../agents/pre-push-static.sh .git/hooks/pre-push

   The gate enforces R-001 ASCII (commit messages too), `bash -n`,
   `shellcheck -x`, and Tier-1 single-grep rules from
   [`agents/bash-style-guide.md`](agents/bash-style-guide.md).
   Push regardless and CI will run the same gate via
   [`.github/workflows/pre-push-static.yml`](.github/workflows/pre-push-static.yml).

3. If the gate fails on a commit message, prefer `git rebase -i`
   to reword over leaving the violation; the user has authorized
   force-pushes for this kind of cleanup on AI-session branches.
