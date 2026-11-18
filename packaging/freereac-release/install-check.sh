#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 Pau Aliagas <linuxnow@gmail.com>
# Install freereac-release on a machine that holds no FreeREAC configuration, then install a package of the channel through the
# repository it adds: the repository is named freereac, its index verifies with the key the package ships, and the package
# resolves from it.
#
#   install-check.sh <freereac-release .rpm or .deb> <package of the channel>
#
# SIGNED=0 skips the signature check of the RPM itself, for a dry run's unsigned build; the repository's metadata and the probe
# package are verified either way. Fedora (dnf5) or Debian, as root.
set -euo pipefail
usage='usage: install-check.sh <freereac-release package> <package of the channel>'
pkg=${1:?$usage}
probe=${2:?$usage}
work=$(mktemp -d)
chmod 755 "$work"
trap 'rm -rf "$work"' EXIT
fail() { echo "FAIL: $*" >&2; exit 1; }
case "$pkg" in
https://*) file=$work/$(basename "$pkg"); curl -fsSL --retry 5 --retry-all-errors --retry-delay 3 --connect-timeout 20 -o "$file" "$pkg" ;;
*) file=$(readlink -f "$pkg") ;;
esac
if command -v dnf >/dev/null; then
    [ ! -e /etc/yum.repos.d/freereac.repo ] || fail "this machine already has a freereac.repo"
    dnf install -y --setopt=install_weak_deps=False "$file"
    rpm --import /etc/pki/rpm-gpg/RPM-GPG-KEY-freereac
    if [ "${SIGNED:-1}" = 1 ]; then
        rpm -K "$file" | tee /dev/stderr | grep -q 'digests signatures OK' || fail "$file does not verify with the shipped key"
    fi
    dnf -y --setopt=retries=10 --setopt=skip_if_unavailable=False makecache --repo freereac || fail "the freereac repository does not load"
    dnf repolist | grep -q '^freereac ' || fail "dnf repolist names no freereac"
    dnf install -y --setopt=install_weak_deps=False --setopt=retries=10 "$probe"
    from=$(dnf repoquery --installed --qf '%{from_repo}\n' "$probe" | head -1)
    [ "$from" = freereac ] || fail "$probe came from '$from'"
    echo "$probe installed from freereac"
else
    [ ! -e /etc/apt/sources.list.d/freereac.sources ] || fail "this machine already has a freereac.sources"
    apt-get install -y --no-install-recommends "$file"
    gpg --show-keys /usr/share/keyrings/freereac-archive-keyring.asc
    apt-get -o Acquire::Retries=5 update 2>&1 | tee "$work/update"
    ! grep -qE '^(W|E):' "$work/update" || fail "apt update with the freereac source warned or failed"
    apt-get install -y --no-install-recommends "$probe"
    apt-cache policy "$probe" | tee "$work/policy"
    grep -q 'freereac.github.io/deb/debian/trixie' "$work/policy" || fail "$probe does not come from the freereac source"
    echo "$probe installed from the freereac source"
fi
echo "install check: PASS"
