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

## systemd >= 256 mounts a tmpfs over /tmp by default (tmp.mount). Inside
## a container that shadows anything `docker cp` writes to /tmp: the copy
## lands in the lower directory while the running system sees the empty
## tmpfs, so copied files silently "vanish". Mask tmp.mount so /tmp stays
## a plain directory on the container filesystem -- `docker cp` to /tmp
## then works and persists, matching pre-256 behaviour.
RUN systemctl mask -- tmp.mount

STOPSIGNAL SIGRTMIN+3

ENTRYPOINT ["/lib/systemd/systemd"]
