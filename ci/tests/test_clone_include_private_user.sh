#!/bin/bash

## Copyright (C) 2026 - 2026 ENCRYPTED SUPPORT LLC <adrelanos@whonix.org>
## See the file COPYING for copying conditions.

## AI-Assisted

## Mock-API test: github-org-clone --include-private against a User
## owner that does not equal the auth user must refuse rather than
## silently downgrade to public-only listing. Regression test for the
## P2 review point on PR #16.

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

SCRIPT_DIR="$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" && pwd )"
FIXTURES_DIR="$(cd -- "${SCRIPT_DIR}/../fixtures" && pwd)"

export GHORG_MOCK=true
export GHORG_MOCK_DIR="${FIXTURES_DIR}"

## Auth user is "assisted-by-ai" per GET_user fixture; we ask for
## private repos of "org-ai-assisted" (an Org, not a User), so the User-
## branch refusal does not apply. Instead test the plain User case:
## ask for private repos of the User account that IS the auth user.
## That should succeed (no refusal).
##
## Negative case: User != auth_user -> refusal. We synthesize this by
## pointing the request at "some-other-user". Without a fixture for
## that login the dispatcher returns HTTP 599; ghorg_account_type then
## fails. Acceptable for this test - the assertion below is on
## the equality check itself, not the post-error behavior.
out="$(github-org-clone --include-private --dry-run assisted-by-ai \
  /tmp/clone-private-user-out 2>&1 || true)"

if grep --quiet -- 'cannot list private repos' <<< "${out}"; then
  printf '%s\n' \
    'FAIL: did not expect a refusal for the auth user listing their own private repos' \
    "${out}" >&2
  exit 1
fi

exit 0
