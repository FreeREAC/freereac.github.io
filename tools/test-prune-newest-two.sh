#!/bin/bash
# prune-newest-two keeps the 2 newest versions of each package per tree, compared as versions (1.0.9 < 1.0.10), and the check is green after.
set -euo pipefail
here=$(dirname "$(readlink -f "$0")"); w=$(mktemp -d)
d=$w/rpm/fedora/44/x86_64; mkdir -p "$d" "$w/deb/debian/trixie/amd64"
for v in 1.0.9 1.0.10 1.0.11; do touch "$d/reac-pw-$v-1.fc44.x86_64.rpm" "$d/reac-pw-devel-$v-1.fc44.x86_64.rpm"; done
for v in 1.9.0 1.10.0 1.11.0; do touch "$w/deb/debian/trixie/amd64/libreac7_${v}_amd64.deb"; done
"$here/check-newest-two.sh" tree "$w" >/dev/null 2>&1 && { echo "FAIL: three versions passed the tree check"; exit 1; }
"$here/prune-newest-two.sh" "$w" >/dev/null
[ ! -e "$d/reac-pw-1.0.9-1.fc44.x86_64.rpm" ] || { echo "FAIL: the oldest was kept (sorted as text?)"; exit 1; }
[ -e "$d/reac-pw-1.0.10-1.fc44.x86_64.rpm" ] && [ -e "$d/reac-pw-1.0.11-1.fc44.x86_64.rpm" ] || { echo "FAIL: a newest-2 version was removed"; exit 1; }
[ -e "$d/reac-pw-devel-1.0.11-1.fc44.x86_64.rpm" ] || { echo "FAIL: reac-pw-devel was mistaken for reac-pw"; exit 1; }
[ ! -e "$w/deb/debian/trixie/amd64/libreac7_1.9.0_amd64.deb" ] || { echo "FAIL: the oldest deb was kept"; exit 1; }
"$here/check-newest-two.sh" tree "$w" >/dev/null
# a root that holds neither tree is refused by name, and nothing under it is touched
mkdir -p "$w/empty-root/elsewhere"; touch "$w/empty-root/elsewhere/keep-1-1.fc44.x86_64.rpm"
if out=$("$here/prune-newest-two.sh" "$w/empty-root" 2>&1); then echo "FAIL: pruning a root with neither tree passed"; exit 1; fi
grep -q 'holds neither rpm/fedora nor deb/debian' <<< "$out" || { echo "FAIL: the refusal does not say why: $out"; exit 1; }
[ -e "$w/empty-root/elsewhere/keep-1-1.fc44.x86_64.rpm" ] || { echo "FAIL: a file outside the trees was removed"; exit 1; }
echo "prune-newest-two: ok"
