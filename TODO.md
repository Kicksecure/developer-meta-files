# TODO

Operator follow-ups surfaced by the GitHub web-settings sweep
(2026-05). Nothing in this file is automated; each item is a
one-off manual UI step or a tool extension that was deliberately
deferred.

## Org-level profile (UI-only, manual)

`org-ai-assisted` profile fields are empty. Suggested values to
fill in via Settings -> Profile:

| Field | Suggested value |
| --- | --- |
| Display name | `AI-Assisted (Kicksecure / Whonix mirror)` |
| Description | `AI-assisted dev fork of every Kicksecure / Whonix repo. Issues, reports, and disclosures belong upstream.` |
| Website (URL) | `https://www.kicksecure.com/` (or `https://www.whonix.org/`) - whichever is canonical for "where to file reports" |
| Email | leave empty |
| Twitter / Mastodon | leave empty unless a project handle exists |
| Location | leave empty |
| Pinned repos (UI-only) | `developer-meta-files` plus 2-3 actively-developed mirrors (e.g. `derivative-maker`, `helper-scripts`, `security-misc`) |

Same revamp arc as the per-repo `homepage` field deprecation
(stale `imprint` URLs replaced with real canonical pages); the
metadata file `metadata/repo-metadata.bsh` already drives that on
the per-repo side.

For the canonical orgs `Kicksecure` and `Whonix` the same fields
are presumably already populated; not worth touching.

## Org-level commit signoff (UI or one-off PATCH)

`org-ai-assisted.web_commit_signoff_required` is currently
`false`. Flipping to `true` once at the org level cascades to all
108 repos in one shot - simpler than the per-repo path
documented in `agents/github-policy-canonical-vs-mirror.md`.

REST: `PATCH /orgs/org-ai-assisted` body
`{"web_commit_signoff_required": true}`. Token needs
`admin:org`.

## Personal-profile field revamp (manual)

PERSON `adrelanos` profile fields:

- `blog`: currently `https://www.kicksecure.com/imprint` -
  same Impressum-URL deprecation as the org repos. Replace with a
  canonical landing page.
- `bio`: empty - one-line tagline would help.
- `social_accounts`: empty - if there is a project Mastodon /
  Bluesky / Twitter, fill in.

BOT `assisted-by-ai` profile fields are intentionally minimal;
no change.

## dm-github-personal-policy filter for `adrelanos`

The personal-policy script is currently unsafe to run against
`adrelanos`. It would clobber `adrelanos/PasswordTrainer` and
`adrelanos/travis.debian.net` Pages sites and disable CI on his
335 repos including standalone projects that are not Kicksecure
/ Whonix mirrors.

Two options for follow-up (not in any open PR):

a) Auto-filter inside the script to only operate on repos where
   `.fork == true` and `.parent.owner.login` is `Kicksecure` or
   `Whonix`. Standalone projects skipped automatically.
b) Per-user explicit allow / deny list declared next to
   `PERSON_USERS`. More maintenance but no surprises.

Until either lands, do not run `dm-github-personal-policy
adrelanos --apply`.

## Future tightenings (already documented)

- `web_commit_signoff_required` at the per-repo level (or org
  level - see above).
- Tag-name pattern ruleset rule like `^v[0-9]+\.[0-9]+(\.[0-9]+)?$`.
- `interaction_limit: collaborators_only` on MIRROR repos.
- Org Copilot `public_code_suggestions: block` (only relevant
  once seats are assigned; currently 0 seats).
- Org-level secret visibility tightening from `all` to
  `selected` for `OPENAI_API_KEY`, `ANTHROPIC_API_KEY`,
  `COVERITY_SCAN_EMAIL`. Operational trade-off: each new
  consumer repo needs explicit add.
- Org template-sync tool to commit `.github/workflows/codeql.yml`
  + `.github/dependabot.yml` shells into every repo (closes the
  104/108 missing-dependabot.yml gap and the 104/108 missing-
  CodeQL-workflow gap).

See `agents/github-policy-canonical-vs-mirror.md` for the full
list with rationale.
