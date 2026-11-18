#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 Pau Aliagas <linuxnow@gmail.com>
# Build freereac-release, the package that adds the FreeREAC repository, with the channel's one public key.
#
#   FREEREAC_RELEASE_KEY_FPR=<fingerprint> build.sh rpm|deb <key file> <output dir>
#
# THE ONE-KEY CHECK. The key file must hold exactly one key and that key's primary fingerprint must be FREEREAC_RELEASE_KEY_FPR,
# the fingerprint of the FreeREAC release key: a file with a second key, another key, or an unset fingerprint is refused and
# nothing is built. The package ships those bytes, so a machine verifies with the one key the channel signs with.
# The RPM's Version-Release and the DEB's version are one release: a build where they differ is refused. rpm runs in a Fedora
# container with rpm-build and gnupg2; deb in a Debian one with dpkg-dev, debhelper, lintian and gnupg, as root.
set -euo pipefail
here=$(dirname "$(readlink -f "$0")")
usage='usage: FREEREAC_RELEASE_KEY_FPR=<fingerprint> build.sh rpm|deb <key file> <output dir>'
kind=${1:?$usage}
key=$(readlink -f "${2:?$usage}")
out=$(readlink -m "${3:?$usage}")
spec=$here/freereac-release.spec
want=${FREEREAC_RELEASE_KEY_FPR:-}
[[ $want =~ ^[0-9A-Fa-f]{40}$ ]] || { echo "FREEREAC_RELEASE_KEY_FPR is '$want', not a key fingerprint: the owner sets it to the channel's release key first" >&2; exit 1; }

version=$(sed -n 's/^Version: *//p' "$spec")
release=$(sed -n 's/^Release: *\([0-9][0-9.]*\)%{?dist}$/\1/p' "$spec")
[ -n "$version" ] && [ -n "$release" ] || { echo "no Version or Release N%{?dist} in $spec" >&2; exit 1; }
debver=$(sed -n '1s/^freereac-release (\([^)]*\)).*/\1/p' "$here/debian/changelog")
[ "$debver" = "$version-$release" ] || { echo "debian/changelog says $debver, the spec $version-$release" >&2; exit 1; }

# exactly one primary key, and it is the channel's
primaries=$(gpg --batch --with-colons --import-options show-only --import < "$key" 2>/dev/null | awk -F: '/^pub:/ {p = 1; next} /^fpr:/ && p {print $10; p = 0}')
[ "$(wc -w <<< "$primaries")" = 1 ] || { echo "$key holds $(wc -w <<< "$primaries") keys ($(tr '\n' ' ' <<< "$primaries")), the channel serves exactly one" >&2; exit 1; }
[ "${primaries^^}" = "${want^^}" ] || { echo "$key holds $primaries, not the $want the channel signs with" >&2; exit 1; }
# the repository file this package installs is the one the channel serves
if [ -f "$here/../../rpm/freereac.repo" ]; then
    cmp "$here/freereac.repo" "$here/../../rpm/freereac.repo" || { echo "freereac.repo differs from the rpm/freereac.repo the channel serves" >&2; exit 1; }
fi

mkdir -p "$out"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
echo "freereac-release $version-$release ($kind) ships $primaries"
case "$kind" in
rpm)
    mkdir -p "$work/SOURCES"
    cp "$here/freereac.repo" "$work/SOURCES/"
    cp "$key" "$work/SOURCES/RPM-GPG-KEY-freereac"
    rpmbuild --define "_topdir $work" -bb "$spec"
    find "$work/RPMS" -name 'freereac-release-*.noarch.rpm' -exec cp {} "$out/" \;
    ls "$out"/freereac-release-*.noarch.rpm
    ;;
deb)
    mkdir -p "$work/src"
    cp -r "$here/debian" "$work/src/debian"
    cp "$key" "$work/src/debian/freereac-archive-keyring.asc"
    (cd "$work/src" && dpkg-buildpackage -b -uc -us && lintian --fail-on error,warning ../freereac-release_*.changes)
    cp "$work"/freereac-release_*_all.deb "$out/"
    ls "$out"/freereac-release_*_all.deb
    ;;
*)
    echo "$usage" >&2
    exit 2
    ;;
esac
