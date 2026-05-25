#!/bin/bash

## Copyright (C) 2026 - 2026 ENCRYPTED SUPPORT LLC <adrelanos@whonix.org>
## See the file COPYING for copying conditions.

## AI-Assisted

## style-ok: no-safe-rm

## Build a Debian-based image with systemd as PID 1 and start it
## detached + --privileged. Not compatible with GHA's `container:`
## directive (overrides ENTRYPOINT); caller runs on the host
## runner without `container:`.

set -o errexit
set -o nounset
set -o pipefail
set -o errtrace
shopt -s inherit_errexit
shopt -s shift_verbose

if [ "${CI:-}" != "true" ]; then
   printf '%s\n' 'error: this script must run with CI=true.' >&2
   exit 1
fi

true "${IMAGE:?IMAGE env var must be set}"
true "${CONTAINER_NAME:?CONTAINER_NAME env var must be set}"
true "${WORKSPACE_MOUNT:?WORKSPACE_MOUNT env var must be set}"
APT_BOOTSTRAP_PACKAGES="${APT_BOOTSTRAP_PACKAGES:-}"
WAIT_SECONDS="${WAIT_SECONDS:-60}"

readonly IMAGE
readonly CONTAINER_NAME
readonly WORKSPACE_MOUNT
readonly APT_BOOTSTRAP_PACKAGES
readonly WAIT_SECONDS

readonly systemd_image_tag="launch-systemd-container-${CONTAINER_NAME}:tmp"

dockerfile_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

printf '%s\n' "=== Building systemd image '${systemd_image_tag}' from '${IMAGE}' ==="
docker build \
   --tag "${systemd_image_tag}" \
   --build-arg "IMAGE=${IMAGE}" \
   --build-arg "APT_BOOTSTRAP_PACKAGES=${APT_BOOTSTRAP_PACKAGES}" \
   -- \
   "${dockerfile_dir}"

docker rm --force -- "${CONTAINER_NAME}" >/dev/null 2>&1 || true

printf '%s\n' "=== Starting container '${CONTAINER_NAME}' with systemd as PID 1 ==="
## /tmp:exec overrides Docker's noexec --tmpfs default so
## equivs-build / dpkg-buildpackage / pip wheels can exec
## generated scripts from mktemp dirs.
docker run \
   --detach \
   --privileged \
   --cgroupns=host \
   --tmpfs /run \
   --tmpfs /run/lock \
   --tmpfs /tmp:exec,rw,nosuid,nodev \
   --name "${CONTAINER_NAME}" \
   --volume "${WORKSPACE_MOUNT}:/workspace" \
   --stop-signal=SIGRTMIN+3 \
   -- \
   "${systemd_image_tag}"

printf '%s\n' "=== Waiting up to ${WAIT_SECONDS}s for systemd to reach a stable state ==="
state=""
attempt=0
while [ "${attempt}" -lt "${WAIT_SECONDS}" ]; do
   attempt=$((attempt + 1))
   state="$(docker exec "${CONTAINER_NAME}" systemctl is-system-running 2>/dev/null || true)"
   printf '  attempt %3d/%-3d state=%s\n' "${attempt}" "${WAIT_SECONDS}" "${state}"
   case "${state}" in
      running|degraded|maintenance)
         break
         ;;
   esac
   sleep 1
done

case "${state}" in
   running|degraded|maintenance)
      printf '%s\n' "=== systemd is up (state: ${state}); container '${CONTAINER_NAME}' is ready ==="
      ;;
   *)
      printf '%s\n' "error: systemd did not reach running/degraded/maintenance in ${WAIT_SECONDS}s (last state: '${state}')" >&2
      docker exec "${CONTAINER_NAME}" systemctl list-units --failed --no-pager >&2 || true
      docker exec "${CONTAINER_NAME}" journalctl --no-pager --lines=50 >&2 || true
      exit 1
      ;;
esac
