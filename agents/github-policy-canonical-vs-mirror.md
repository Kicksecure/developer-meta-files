# Canonical vs mirror policy split (AI-Assisted)

The dm-github-* tool family applies the same baseline policy to two
classes of repository, with a small set of deliberate diffs driven
by canonical-vs-mirror role. Companion to
[github-org-tools.md](github-org-tools.md).

The four roles are:

| Role | Where it lives | Tool that touches it |
| --- | --- | --- |
| SOURCE | Kicksecure, Whonix orgs | dm-github-org-policy, kind=source |
| MIRROR | org-ai-assisted org | dm-github-org-policy, kind=mirror |
| PERSON | PERSON_USERS array | dm-github-personal-policy, target_kind=person |
| BOT | BOT_USERS array | dm-github-personal-policy, target_kind=bot |

Only SOURCE is canonical. The other three are mirrors of upstream
work. The deliberate diffs below all follow from that single split.

## Free-plan code-security replacements

Applied per-repo on the org side after the org-level Code Security
Configurations API turned out to be PAID PLAN ONLY. SOURCE-only on
purpose: a mirror running these would duplicate every alert the
canonical SOURCE repo already raises. Empirically tested on Free
2026-05.

| Feature | SOURCE | MIRROR | PERSON | BOT |
| --- | --- | --- | --- | --- |
| Dependabot alerts (`PUT /vulnerability-alerts` enable, `DELETE` on MIRROR) | on | actively disabled | off | off |
| Dependabot security updates (`PUT /automated-security-fixes` enable, `DELETE` on MIRROR) | on | actively disabled | off | off |
| Private vulnerability reporting (`PUT /private-vulnerability-reporting` enable, `DELETE` on MIRROR) | on | actively disabled | off | off |
| `secret_scanning` + push protection (in PATCH body) | on | on | on | on |
| Branch + tag rulesets (`POST /repos/{}/{}/rulesets`) | on | on | on | on |

Notes:

- Dependabot / PVR (Private Vulnerability Reporting) off on
  MIRROR/PERSON/BOT for the same reason: split inbox / duplicate
  notifications. On MIRROR `apply_repo_policy` actively DELETEs
  the three settings (every `--apply` reconciles), so leftovers
  from older un-gated runs or accidental UI flips are cleaned
  up. Order: DEPENDABOT_FIXES_OFF before DEPENDABOT_ALERTS_OFF -
  the security-fixes endpoint returns HTTP 422 once alerts are
  off, which is the idempotent steady state and is captured as
  ok via the `_EXTRA_OK_STATUS=422` knob (see G-035 in
  `github-org-tools.md`). On PERSON/BOT
  `dm-github-personal-policy` keeps step 8 commented out for the
  same reason (with the canonical-home-uncomment note); the
  personal mirror never had these on so an active-disable pass
  is unnecessary.
- Secret scanning + push protection are about local git ops, not
  inbox routing, so they stay on everywhere.
- Rulesets stay on everywhere; only the bypass-actor list pivots
  (see Summary table below).

## Summary of intentional canonical-vs-mirror splits

| Axis | Canonical (SOURCE) | Mirror (MIRROR / PERSON / BOT) |
| --- | --- | --- |
| Issue tracking | `has_issues=on` | `has_issues=off` (route upstream) |
| Project boards / discussions / wikis | (default on, unset) | off |
| Ruleset bypass | `[]` (no bypass) | `[OrgAdmin]` on MIRROR; `[]` on PERSON/BOT |
| CI / Actions | enabled, allow-list = github-owned + verified-creators | disabled entirely on PERSON/BOT (mirrors only); MIRROR keeps CI on (it is where AI-assisted dev runs) |
| Dependabot alerts + security updates + PVR (Private Vulnerability Reporting) | on | off (would duplicate upstream alerts) |
| GitHub Pages site | not touched | `DELETE /pages` on PERSON/BOT (mirror should not host Pages) |

Net deliberate diffs after this split:

1. `has_issues=on` only on SOURCE. Everywhere else issues route
   upstream.
2. `[OrgAdmin]` ruleset bypass only on MIRROR (hotfix re-fork
   without dropping the ruleset); SOURCE/PERSON/BOT have no bypass.
3. CI disabled entirely on PERSON/BOT (no workflows run on the
   personal mirrors); SOURCE/MIRROR run CI under the same selected-
   actions allow-list.
4. Dependabot + PVR (Private Vulnerability Reporting) enabled
   only on SOURCE.
5. GitHub Pages cleanup (DELETE) only on PERSON/BOT.

Everything else (fork-PR approval policy, workflow GITHUB_TOKEN
permissions, secret scanning, rulesets) is identical content with
only the API scope (org-level vs per-repo) differing.

## Potential future tightenings (not in policy yet)

Surfaced during the 2026-05 GitHub web-settings sweep. Each is a
low-risk addition; landing them is gated only on operator
appetite for the friction trade-off.

- **`web_commit_signoff_required: true`** in the per-repo PATCH
  body (`POLICY_REPO_*`). Closes a small bypass against the
  GPG-required-signatures ruleset: web-UI commits ("edit this
  file" / suggestion-accept / web upload) currently produce
  commits signed only by GitHub's web-flow GPG key, not the
  contributor's. With this on, web edits also require a
  `Signed-off-by:` DCO trailer (textual, no PGP key, just a
  checkbox in the commit form). Friction: one extra checkbox
  click on web edits. No CLI workflow impact. Apply to SOURCE
  and MIRROR alike.

- **Tag-name pattern ruleset rule** like
  `^v[0-9]+\.[0-9]+(\.[0-9]+)?$` on the tag ruleset. Catches
  the rare class of "tag with wrong format" pushes that the
  current rules let through. May need a bypass exemption if
  hotfix tags ever use a different shape.

- **`interaction_limit: collaborators_only`** permanently on
  MIRROR repos via `PUT /repos/{}/{}/interaction-limits`.
  Issues / discussions are off everywhere on MIRROR so there is
  not much to interact with, but a hostile drive-by PR would be
  silently rejected at the API instead of opening a noisy issue
  in the maintainer's queue.

- **Audit flag for private repos** in `audit_org_state`. None
  exist today, but a regression (someone flipping a public repo
  to private via the UI) would silently break secret scanning +
  push protection on the affected repo since GHAS is required
  for those features on private Free-org repos. Read-only check;
  no apply mutation.

`sha_pinning_required: true` is intentionally NOT in this list -
see `agents/github-actions.md` "Org-level `sha_pinning_required`
is intentionally OFF" for the rationale.
