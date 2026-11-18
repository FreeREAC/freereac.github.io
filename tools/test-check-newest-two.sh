#!/bin/bash
# The newest-2 check is red on three versions, naming the package, and green on two.
set -euo pipefail
here=$(dirname "$(readlink -f "$0")"); w=$(mktemp -d)
printf 'rpm rpm/fedora/44/x86_64 reac-pw-1.0.%s-1.fc44.x86_64.rpm aa\n' 42 43 44 > "$w/three"
head -n 2 "$w/three" > "$w/two"
printf 'deb deb/debian/trixie/amd64 libreac7_1.%s.0_amd64.deb aa\n' 9 10 11 > "$w/debs"
"$here/check-newest-two.sh" manifest "$w/two" >/dev/null || { echo "FAIL: two versions refused"; exit 1; }
if out=$("$here/check-newest-two.sh" manifest "$w/three" 2>&1); then echo "FAIL: three rpm versions accepted"; exit 1; fi
grep -q 'reac-pw has 3 versions' <<< "$out" || { echo "FAIL: the refusal does not name the package: $out"; exit 1; }
if "$here/check-newest-two.sh" manifest "$w/debs" >/dev/null 2>&1; then echo "FAIL: three deb versions accepted"; exit 1; fi
"$here/check-newest-two.sh" manifest "$here/../import/manifest.txt" >/dev/null
echo "check-newest-two: ok"
