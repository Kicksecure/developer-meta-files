#!/bin/bash

## Copyright (C) 2026 - 2026 ENCRYPTED SUPPORT LLC <adrelanos@whonix.org>
## See the file COPYING for copying conditions.

## AI-Assisted

## Functional test for the pre-push-static single-grep style checks: assert that
## R-070 (';;' trailing a statement), R-074 (';'-chained break/continue/return),
## R-030/R-031 (a newline printf missing its explicit "" data argument), R-042
## (a blank-line separator), R-034 (echo run as a command), R-011 (set +e),
## R-051 (a quoted inline trap), R-090 (command -v), R-102 (an extensionless
## 'bash script' operand), R-120 (a separator-glued/adjacent rm), and R-010
## (distinct strict-mode directives) actually FLAG a violating shell file and
## SPARE a compliant one. It drives the
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
   ## Liveness guard: require the gate's TERMINAL verdict line, not just any
   ## 'pre-push-static:' note. Early notes ('no changed shell files',
   ## 'shellcheck not on PATH; skipping') would otherwise satisfy a weaker
   ## check even if the gate crashed before reaching the rule under test, so
   ## an 'absent' assertion could pass spuriously on a real regression.
   if ! printf '%s\n' "${out}" \
      | grep --quiet --extended-regexp 'all static checks passed|[0-9]+ check\(s\) failed'; then
      printf 'FAIL: gate produced no final verdict for body %s\n' "'${body}'" >&2
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

## Fragments for the printf-newline assertions, assembled the same way so a
## literal bad-form printf never appears in this tracked file (which the gate
## would, correctly, trip over).
sq="'"
dq='"'
## Literal backslash-n (two chars), single-quoted so it is not interpreted.
nl='\n'
## A literal space and 'rm' as a value, so assertion bodies needing a real
## space-before-'rm' (R-120) or 'command -v' (R-090) do not embed a token
## the gate would flag in THIS tracked file.
sp=' '
del='rm'

## R-074: a ';'-chained break / continue / return must be FLAGGED; the same
## keyword on its own line must be SPARED.
expect_rule "R-074" "hit=1${sc} break"       "present"
expect_rule "R-074" "seen=1${sc} continue"   "present"
expect_rule "R-074" "printf x${sc} return 1" "present"
expect_rule "R-074" "break"                  "absent"

## Whitespace on either side of the ';' is the same violation and must also be
## FLAGGED -- guards against a regex that only anchors on a non-space char
## immediately before the ';'. The bodies below assemble the separator from
## ${sc} at run time, so the literal never appears in this tracked file.
expect_rule "R-074" "hit=1 ${sc} break"      "present"
expect_rule "R-074" "printf y ${sc} return"  "present"

## Word boundary: a keyword that is only a PREFIX of an identifier
## ('return_value', 'continue_calls') must be SPARED, not flagged.
expect_rule "R-074" "x=1${sc}${sp}return_value=1" "absent"

## R-070: ';;' trailing a statement must be FLAGGED; ';;' on its own line spared.
expect_rule "R-070" "esac${dsemi}"           "present"
expect_rule "R-070" "${dsemi}"               "absent"

## R-030/R-031: a newline emitted without an explicit '' data argument must be
## FLAGGED -- both 'printf \n' (newline in the format) and a bare 'printf %s\n'
## (data arg omitted). The compliant 'printf %s\n' "" and a normal data printf
## must be SPARED by this rule (the blank-separator form is R-042's job, below).
expect_rule "R-030/R-031" "printf ${sq}${nl}${sq}"              "present"
expect_rule "R-030/R-031" "printf ${sq}%s${nl}${sq}"            "present"
expect_rule "R-030/R-031" "printf ${sq}%s${nl}${sq} ${dq}${dq}" "absent"
expect_rule "R-030/R-031" "printf ${sq}%s${nl}${sq} hello"      "absent"
## A trailing comment does not supply a data argument, so a commented bare
## form is still a violation; the compliant form stays spared even commented.
expect_rule "R-030/R-031" "printf ${sq}%s${nl}${sq} # blank"        "present"
expect_rule "R-030/R-031" "printf ${sq}%s${nl}${sq} ${dq}${dq} # ok" "absent"

## The compliant 'printf %s\n' "" IS a blank-line separator, so R-042 (not
## R-031) is the rule that owns it -- proves the two checks divide the work
## cleanly rather than both firing or both missing.
expect_rule "R-042" "printf ${sq}%s${nl}${sq} ${dq}${dq}"       "present"

## R-034: 'echo' run as a command must be FLAGGED; 'echo' as a bareword inside
## a string or as another command's argument must be SPARED (the command-
## position anchoring that replaced the old '[[:space:]]echo' form).
expect_rule "R-034" "echo hi"                                   "present"
## echo run as a condition command (line-start keyword) must also be FLAGGED.
expect_rule "R-034" "if echo hi${sc} then"                      "present"
expect_rule "R-034" "printf ${sq}%s${nl}${sq} ${dq}a echo b${dq}" "absent"
expect_rule "R-034" "has echo"                                  "absent"

## R-070: ';;' must be on its own line. Both the jammed ('esac;;') and the
## spaced ('esac ;;') compact forms are FLAGGED; only a bare ';;' is spared.
expect_rule "R-070" "esac${sp}${dsemi}"                          "present"

## R-042: a DOUBLE-quoted blank-separator format is the same violation.
expect_rule "R-042" "printf ${dq}%s${nl}${dq} ${dq}${dq}"        "present"

## R-011: both the long toggle and the short 'set +e' must be FLAGGED.
expect_rule "R-011" "set +o errexit"                             "present"
expect_rule "R-011" "set +e"                                     "present"

## R-051: a double-quoted inline trap command is FLAGGED; clearing a trap
## with an empty string is SPARED.
expect_rule "R-051" "trap ${dq}${del} -f x${dq} EXIT"            "present"
expect_rule "R-051" "trap ${dq}${dq} EXIT"                       "absent"

## R-090: 'command -v' in code is FLAGGED; in a comment it is SPARED.
expect_rule "R-090" "if ! command${sp}-v foo"                    "present"
expect_rule "R-090" "## uses command${sp}-v not has"             "absent"

## R-102: an extensionless but slashed path operand is FLAGGED; a flag or a
## variable operand is SPARED. (Body assembled below via ${sp} so this
## comment carries no literal invocation.)
expect_rule "R-102" "bash${sp}ci/dry-run-start"                  "present"
expect_rule "R-102" "sh${sp}/usr/local/bin/foo"                  "present"
expect_rule "R-102" "bash${sp}--norc script"                     "absent"
expect_rule "R-102" "bash${sp}\${script}"                        "absent"
## A short flag ending in 'sh' and a .sh script run AS the command (with a
## path argument) are NOT interpreter prepends; both matched the old '\b'
## anchor ('\b' also fires after '-' and '.'), so pin them SPARED.
expect_rule "R-102" "du${sp}-sh${sp}/home/user/.cache"           "absent"
expect_rule "R-102" "run${sp}wrapper.sh${sp}/etc/config"         "absent"

## R-120: a separator-glued 'rm', and a real 'rm' next to a safe-rm on one
## line, are both FLAGGED (the invert no longer spares the whole line).
expect_rule "R-120" "true${sc}${del} -rf x"                      "present"
expect_rule "R-120" "safe-${del} -- a${sc}${sp}${del} -rf b"     "present"

## R-010: six COPIES of one directive must NOT satisfy the block (DISTINCT
## directives are counted); the six distinct directives pass.
sixsame=$'set -o errexit\nset -o errexit\nset -o errexit\nset -o errexit\nset -o errexit\nset -o errexit'
sixdistinct=$'set -o errexit\nset -o nounset\nset -o pipefail\nset -o errtrace\nshopt -s inherit_errexit\nshopt -s shift_verbose'
expect_rule "R-010" "${sixsame}"                                 "present"
expect_rule "R-010" "${sixdistinct}"                             "absent"

## R-080: a 'shellcheck source=' path must be relative, anchored with ./ or
## ../ (start with '.'). An absolute path OR a bare name (no ./) is FLAGGED.
expect_rule "R-080" "# shellcheck source=get_colors.sh"          "present"
expect_rule "R-080" "# shellcheck source=/usr/lib/foo.sh"        "present"
expect_rule "R-080" "# shellcheck source=./get_colors.sh"        "absent"
expect_rule "R-080" "# shellcheck source=../../foo.sh"           "absent"

if [ "${failures}" -ne 0 ]; then
   printf '%s\n' "test_pre_push_static_style_rules: ${failures} assertion(s) FAILED." >&2
   exit 1
fi
printf '%s\n' "test_pre_push_static_style_rules: OK -- R-070, R-074, R-030/R-031, R-042, R-034, R-011, R-051, R-090, R-102, R-120 and R-010 enforced as expected."
