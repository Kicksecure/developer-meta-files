#!/bin/bash

## Copyright (C) 2026 - 2026 ENCRYPTED SUPPORT LLC <adrelanos@whonix.org>
## See the file COPYING for copying conditions.

## AI-Assisted

## Secret-isolation regression guard. Driven by
## .github/workflows/reusable-secrets-audit.yml. Presence flags
## arrive as boolean env vars computed at expression-evaluation
## time; secret values themselves never reach this script.

set -o errexit
set -o nounset
set -o pipefail
set -o errtrace
shopt -s inherit_errexit
shopt -s shift_verbose

if [ "${CI:-}" != "true" ] && [ "${ALLOW_LOCAL:-}" != "true" ]; then
  printf '%s\n' "${BASH_SOURCE[0]}: refusing to run outside CI. Set ALLOW_LOCAL=true to override." >&2
  exit 1
fi

fail=0

printf 'ANTHROPIC_API_KEY present:   %s\n' "${ANTHROPIC_PRESENT:-unknown}"
printf 'OPENAI_API_KEY present:      %s\n' "${OPENAI_PRESENT:-unknown}"
printf 'COVERITY_SCAN_TOKEN present: %s\n' "${COVERITY_TOKEN_PRESENT:-unknown}"
printf 'COVERITY_SCAN_EMAIL present: %s\n' "${COVERITY_EMAIL_PRESENT:-unknown}"

if [ "${OPENAI_PRESENT:-}" = "true" ]; then
  printf '%s\n' '::error::OPENAI_API_KEY leaked into the reusable secrets context' >&2
  fail=1
fi

if [ "${COVERITY_TOKEN_PRESENT:-}" = "true" ]; then
  printf '%s\n' '::error::COVERITY_SCAN_TOKEN leaked into the reusable secrets context' >&2
  fail=1
fi

if [ "${COVERITY_EMAIL_PRESENT:-}" = "true" ]; then
  printf '%s\n' '::error::COVERITY_SCAN_EMAIL leaked into the reusable secrets context' >&2
  fail=1
fi

if [ "${ANTHROPIC_PRESENT:-}" != "true" ]; then
  printf '%s\n' '::warning::ANTHROPIC_API_KEY not forwarded by caller' >&2
fi

exit "${fail}"
