## Copyright (C) 2026 - 2026 ENCRYPTED SUPPORT LLC <adrelanos@whonix.org>
## See the file COPYING for copying conditions.

## AI-Assisted

ARG IMAGE=debian:trixie
FROM ${IMAGE}

ARG APT_BOOTSTRAP_PACKAGES=""

ENV DEBIAN_FRONTEND=noninteractive
ENV container=docker

RUN apt-get update \
 && apt-get install --yes --no-install-recommends -- \
      systemd-sysv \
      dbus \
      dbus-user-session \
      ${APT_BOOTSTRAP_PACKAGES} \
 && apt-get clean \
 && rm --recursive --force -- /var/lib/apt/lists/*

## firstboot/udevd/modules-load fail in an unprivileged container
## userland and would taint `systemctl is-system-running`.
RUN systemctl mask -- \
      systemd-firstboot.service \
      systemd-udevd.service \
      systemd-modules-load.service

STOPSIGNAL SIGRTMIN+3

ENTRYPOINT ["/lib/systemd/systemd"]
