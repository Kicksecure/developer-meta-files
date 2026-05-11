#!/bin/bash

## Copyright (C) 2026 - 2026 ENCRYPTED SUPPORT LLC <adrelanos@whonix.org>
## See the file COPYING for copying conditions.

## AI-Assisted

## Install both:
##   * 'pre-commit' framework (the runner that reads
##     .pre-commit-config.yaml and dispatches to hooks).
##   * 'pre-commit-hooks' binaries (check-added-large-files,
##     check-yaml, ...). These are 'language: system' in our config
##     so the framework calls them directly.
##
## Tries Debian apt first
## (https://packages.debian.org/trixie/all/pre-commit-hooks/filelist),
## falls back to PyPI on environments where either package is
## missing. Ubuntu 24.04 noble ships 'pre-commit' the framework but
## NOT 'pre-commit-hooks' the binary set, so the binaries land via
## pip on github-actions ubuntu-latest.
##
## Both paths place the same upstream code on PATH. Callers
## (ci/precommit-hooks-gate.sh, the CI workflow) invoke
## 'pre-commit' by bare name; 'pre-commit' itself invokes the
## individual hook binaries by bare name.

set -o errexit
set -o nounset
set -o pipefail
set -o errtrace
shopt -s inherit_errexit
shopt -s shift_verbose

note() {
   printf '%s\n' "install-pre-commit-hooks: ${1}" >&2
}

sudo_if_needed() {
   if [ "$(id --user)" -eq 0 ]; then
      "${@}"
   else
      sudo "${@}"
   fi
}

install_apt_or_pip() {
   local pkg
   pkg="${1}"
   if sudo_if_needed apt-get install --yes --quiet "${pkg}" 2>/dev/null; then
      note "installed '${pkg}' via apt-get"
      return 0
   fi
   note "apt-get does not have '${pkg}'; falling back to pip"
   sudo_if_needed apt-get install --yes --quiet python3-pip
   ## --break-system-packages: PEP 668 marks system Python as
   ## managed. Acceptable in disposable CI runners; the pip
   ## install delivers the same upstream code as the apt package
   ## would have.
   pip install --break-system-packages "${pkg}"
   note "installed '${pkg}' via pip"
}

install_apt_or_pip pre-commit
install_apt_or_pip pre-commit-hooks
