#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 Pau Aliagas <linuxnow@gmail.com>
# The repository file freereac-release installs names the channel's TWO dnf trees, as openmixer.repo does: freereac (fedora/<release>/$basearch)
# and freereac-noarch (fedora/<release>/noarch), both checked, metadata and packages, with the one key. The architecture directories hold what
# the import places (the OpenMixer channel's noarch packages go inside each of them); the noarch/ tree holds what the shared publish places
# there (freereac-release, future noarch releases per the release matrix), which a client with only the first repository would never read.
set -euo pipefail
here=$(dirname "$(readlink -f "$0")")
f=$here/freereac.repo
fail() { echo "FAIL: $*" >&2; exit 1; }
section() { awk -v id="[$1]" '$0 == id {p = 1; next} /^\[/ {p = 0} p' "$f"; }
for pair in "freereac:/\$basearch/" "freereac-noarch:/noarch/"; do
    id=${pair%%:*}; tail=${pair#*:}
    s=$(section "$id"); [ -n "$s" ] || fail "$f has no [$id] repository"
    grep -q "^baseurl=https://freereac.github.io/rpm/fedora/\$releasever$tail\$" <<< "$s" || fail "[$id] does not read fedora/\$releasever$tail"
    for want in enabled=1 gpgcheck=1 repo_gpgcheck=1 gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-freereac; do
        grep -qx "$want" <<< "$s" || fail "[$id] lacks $want"
    done
done
keys=$(grep -h '^gpgkey=' "$f" | sort -u | wc -l)
[ "$keys" = 1 ] || fail "the repositories name $keys keys, the channel has one"
[ -f "$here/../../rpm/freereac.repo" ] && ! cmp -s "$f" "$here/../../rpm/freereac.repo" && fail "rpm/freereac.repo, the file the channel serves, differs from this one" || true
echo "freereac.repo: ok"
