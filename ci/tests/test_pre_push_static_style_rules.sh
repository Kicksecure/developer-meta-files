#!/bin/bash

## Copyright (C) 2026 - 2026 ENCRYPTED SUPPORT LLC <adrelanos@whonix.org>
## See the file COPYING for copying conditions.

## AI-Assisted

## Functional test for the pre-push-static single-grep style checks: assert that
## R-070 (';;' trailing a statement) and R-074 (';'-chained break/continue/return)
## actually FLAG a violating shell file and SPARE a compliant one. It drives the
## real, shipped agents/pre-push-static.sh as a subprocess against a throwaway git
## repo, so it exercises the check end to end (regex + file selection + reporting),
## not a private copy of the regex.
##
## Every violation snippet is assembled at RUN TIME -- the ';' comes from a
## variable, never a literal -- so neither this test file nor the repository
## carries a ';'-chained keyword that the gate would (correctly) trip over.

set -o errexit
set -o nounset
set -o pipefail
set -o errtrace
shopt -s inherit_errexit
shopt -s shift_verbose

if [ "${CI:-}" != "true" ]; then
   printf '%s\n' \
      'error: this script must run with CI=true (GitHub Actions or equivalent).' >&2
   exit 1
fi

# shellcheck source=../../../helper-scripts/usr/libexec/helper-scripts/has.sh
source /usr/libexec/helper-scripts/has.sh

has git \
   || { printf '%s\n' 'error: git not found on PATH; install via apt.' >&2; exit 1; }
has safe-rm \
   || { printf '%s\n' 'error: safe-rm not found on PATH; install via apt.' >&2; exit 1; }

SCRIPT_DIR="$(cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" && pwd)"
REPO_ROOT="$(cd -- "${SCRIPT_DIR}/../.." && pwd)"
GATE="${REPO_ROOT}/agents/pre-push-static.sh"

[ -x "${GATE}" ] \
   || { printf '%s\n' "error: gate not executable at '${GATE}'." >&2; exit 1; }

tmp_root="$(mktemp --directory)"
cleanup() {
   safe-rm --recursive --force -- "${tmp_root}"
}
trap cleanup EXIT

failures=0

## Build a throwaway repo whose HEAD adds sample.sh (a shebang + the given body)
## on top of an empty base, run the gate against that base, and echo its combined
## output. The body is untrusted text placed only in a /tmp repo, never committed
## to developer-meta-files, so it cannot self-trip this repo's own gate.
gate_output() {
   local body repo base
   body="$1"
   repo="$(mktemp --directory --tmpdir="${tmp_root}" repo.XXXXXX)"
   git -C "${repo}" init --quiet
   git -C "${repo}" config user.email 'ci-test@example.com'
   git -C "${repo}" config user.name 'ci-test'
   git -C "${repo}" commit --quiet --allow-empty --message base
   base="$(git -C "${repo}" rev-parse HEAD)"
   printf '#!/bin/bash\n%s\n' "${body}" > "${repo}/sample.sh"
   git -C "${repo}" add sample.sh
   git -C "${repo}" commit --quiet --message sample
   (
      cd -- "${repo}" || exit 1
      "${GATE}" "${base}"
   ) 2>&1 || true
}

## expect_rule <rule-tag> <sample-body> <present|absent>
## Assert the gate output does / does not carry <rule-tag> for the sample body.
expect_rule() {
   local tag body want out got
   tag="$1"
   body="$2"
   want="$3"
   out="$(gate_output "${body}")"
   ## Liveness guard: every gate run prints at least one 'pre-push-static:' line
   ## (via note/fail). If none is present the gate did not reach a verdict (it
   ## errored early), so an 'absent' result would be meaningless -- fail loudly
   ## rather than pass an 'absent' assertion spuriously.
   if ! printf '%s\n' "${out}" | grep --quiet --fixed-strings -- 'pre-push-static:'; then
      printf 'FAIL: gate produced no verdict output for body %s\n' "'${body}'" >&2
      failures=$((failures + 1))
      return 0
   fi
   if printf '%s\n' "${out}" | grep --quiet --fixed-strings -- "${tag}"; then
      got="present"
   else
      got="absent"
   fi
   if [ "${got}" = "${want}" ]; then
      printf 'PASS: %s %-7s for body %s\n' "${tag}" "${want}" "'${body}'"
   else
      printf 'FAIL: %s expected %s but was %s for body %s\n' \
         "${tag}" "${want}" "${got}" "'${body}'" >&2
      failures=$((failures + 1))
   fi
}

## ';' and ';;' assembled here so the literals never appear in tracked source.
sc=';'
dsemi=';;'

## R-074: a ';'-chained break / continue / return must be FLAGGED; the same
## keyword on its own line must be SPARED.
expect_rule "R-074" "hit=1${sc} break"       "present"
expect_rule "R-074" "seen=1${sc} continue"   "present"
expect_rule "R-074" "printf x${sc} return 1" "present"
expect_rule "R-074" "break"                  "absent"

## Whitespace around the ';' ('foo ; break') is the same violation and must also
## be FLAGGED -- guards against a regex that only anchors on a non-space char
## immediately before the ';'.
expect_rule "R-074" "hit=1 ${sc} break"      "present"
expect_rule "R-074" "printf y ${sc} return"  "present"

## R-070: ';;' trailing a statement must be FLAGGED; ';;' on its own line spared.
expect_rule "R-070" "esac${dsemi}"           "present"
expect_rule "R-070" "${dsemi}"               "absent"

if [ "${failures}" -ne 0 ]; then
   printf '%s\n' "test_pre_push_static_style_rules: ${failures} assertion(s) FAILED." >&2
   exit 1
fi
printf '%s\n' "test_pre_push_static_style_rules: OK -- R-070 and R-074 enforced as expected."
