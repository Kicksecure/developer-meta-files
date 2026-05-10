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
| Private vulnerability reporting (PVR) - `DELETE /private-vulnerability-reporting` everywhere | actively disabled | actively disabled | off | off |
| `secret_scanning` + push protection (in PATCH body) | on | on | on | on |
| Branch + tag rulesets (`POST /repos/{}/{}/rulesets`) | on | on | on | on |

Notes:

- Dependabot off on MIRROR/PERSON/BOT for the split-inbox /
  duplicate-notifications reason. On MIRROR `apply_repo_policy`
  actively DELETEs the two Dependabot settings (every `--apply`
  reconciles), so leftovers from older un-gated runs or
  accidental UI flips are cleaned up. Order: DEPENDABOT_FIXES_OFF
  before DEPENDABOT_ALERTS_OFF - the security-fixes endpoint
  returns HTTP 422 once alerts are off, which is the idempotent
  steady state and is captured as ok via the
  `_EXTRA_OK_STATUS=422` knob (see G-035 in
  `github-org-tools.md`). On PERSON/BOT
  `dm-github-personal-policy` keeps step 8 commented out for the
  same reason (with the canonical-home-uncomment note); the
  personal mirror never had these on so an active-disable pass
  is unnecessary.

- PVR (Private Vulnerability Reporting) is off on EVERY role,
  including SOURCE. The canonical disclosure channel for
  Kicksecure / Whonix is the wiki (linked from the SECURITY.md
  committed at `org-ai-assisted/.github/SECURITY.md`, pointing
  to https://www.kicksecure.com/wiki/Reporting_Bugs#
  Security_Vulnerabilities and the Vulnerability Disclosure
  Policy page). Enabling PVR on top of that would split the
  disclosure inbox between the wiki flow and a parallel
  GitHub-side flow. `apply_repo_policy` actively DELETEs PVR on
  every repo unconditionally; there is no PUT-style enable
  constant in `github-policy-data.bsh`.
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
| Dependabot alerts + security updates | on | off (would duplicate upstream alerts) |
| PVR (Private Vulnerability Reporting) | **off everywhere** (canonical disclosure is the wiki - see `.github/SECURITY.md`) | off |
| GitHub Pages site | not touched | `DELETE /pages` on PERSON/BOT (mirror should not host Pages) |

Net deliberate diffs after this split:

1. `has_issues=on` only on SOURCE. Everywhere else issues route
   upstream.
2. `[OrgAdmin]` ruleset bypass only on MIRROR (hotfix re-fork
   without dropping the ruleset); SOURCE/PERSON/BOT have no bypass.
3. CI disabled entirely on PERSON/BOT (no workflows run on the
   personal mirrors); SOURCE/MIRROR run CI under the same selected-
   actions allow-list.
4. Dependabot enabled only on SOURCE; PVR (Private Vulnerability
   Reporting) actively disabled everywhere because the canonical
   disclosure channel is the wiki (per `.github/SECURITY.md`),
   not GitHub's PVR flow.
5. GitHub Pages cleanup (DELETE) only on PERSON/BOT.

Everything else (fork-PR approval policy, workflow GITHUB_TOKEN
permissions, secret scanning, rulesets) is identical content with
only the API scope (org-level vs per-repo) differing.

## Potential future tightenings (not in policy yet)

Surfaced during the 2026-05 GitHub web-settings sweep. Each is a
low-risk addition; landing them is gated only on operator
appetite for the friction trade-off.

- **`web_commit_signoff_required: true`** at the org level (or
  per-repo via `POLICY_REPO_*`). NOT a security setting and NOT
  related to GPG. Forces commits made through the GitHub web UI
  ("edit this file" / suggestion-accept / web upload) to carry a
  `Signed-off-by: Name <email>` trailer - the textual DCO
  attestation (https://developercertificate.org/) that the
  contributor has the right to submit the code under the
  project's license. Same thing the Linux kernel and many other
  projects require on every patch. Worth enabling only if
  Kicksecure / Whonix wants to formally adopt the DCO sign-off
  contribution model; otherwise it just adds a UI checkbox click
  with no benefit. The cryptographic-signature requirement is a
  separate concern handled by the existing `required_signatures`
  ruleset rule, which web-UI commits already satisfy via
  GitHub's web-flow GPG key.

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

- **Org Copilot `public_code_suggestions: block`** (currently
  `allow`). Moot today - 0 seats assigned - but the moment a
  seat lands, blocking verbatim public-code suggestions reduces
  the risk of GPL / BSD-licensed snippets being accepted into
  Kicksecure / Whonix without their attribution. Org-level UI
  toggle, not in any of our policy scripts.

`sha_pinning_required: true` is intentionally NOT in this list -
see `agents/github-actions.md` "Org-level `sha_pinning_required`
is intentionally OFF" for the rationale.
