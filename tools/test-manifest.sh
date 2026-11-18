#!/bin/bash
# manifest.py against a fixture channel (a directory laid out like the served one): generate keeps the newest 2 versions per package per
# tree; verify refuses a line the index lists nowhere there (the stale-manifest case: a noarch rpm that moved from x86_64/ to noarch/), a
# wrong sha256, and passes a manifest generated from the channel. No network, no rpm tools: the indexes are written here.
set -euo pipefail
here=$(dirname "$(readlink -f "$0")"); w=$(mktemp -d)
python3 -I - "$w" <<'PY'
import gzip, os, sys
w = sys.argv[1]
def repo(rel, arch, pkgs):
    d = f"{w}/rpm/fedora/{rel}/{arch}/repodata"; os.makedirs(d)
    x = '<?xml version="1.0"?>\n<metadata xmlns="http://linux.duke.edu/metadata/common">\n'
    for n, v, r, a, sha in pkgs:
        x += (f'<package type="rpm"><name>{n}</name><arch>{a}</arch><version epoch="0" ver="{v}" rel="{r}"/>'
              f'<checksum type="sha256" pkgid="YES">{sha}</checksum><location href="{n}-{v}-{r}.{a}.rpm"/></package>\n')
    open(f"{d}/primary.xml.gz", "wb").write(gzip.compress((x + "</metadata>\n").encode()))
    open(f"{d}/repomd.xml", "w").write('<?xml version="1.0"?>\n<repomd xmlns="http://linux.duke.edu/metadata/repo"><data type="primary">'
                                       '<location href="repodata/primary.xml.gz"/></data></repomd>\n')
h = lambda c: c * 64
repo("44", "x86_64", [("reac-pw", v, "1.fc44", "x86_64", h(str(i))) for i, v in enumerate(["1.0.9", "1.0.10", "1.0.11"], 1)]
     + [("other-thing", "1", "1.fc44", "x86_64", h("f"))])
repo("44", "noarch", [("reac-pw-devel", "1.0.11", "1.fc44", "noarch", h("a"))])
os.makedirs(f"{w}/deb/debian/trixie")
open(f"{w}/deb/debian/trixie/Packages", "w").write(
    "Package: libreac7\nVersion: 1.11.0\nArchitecture: amd64\nFilename: ./amd64/libreac7_1.11.0_amd64.deb\nSHA256: " + h("b") + "\n\n"
    "Package: libreac7\nVersion: 1.10.0\nArchitecture: amd64\nFilename: ./amd64/libreac7_1.10.0_amd64.deb\nSHA256: " + h("c") + "\n\n"
    "Package: libreac7\nVersion: 1.9.0\nArchitecture: amd64\nFilename: ./amd64/libreac7_1.9.0_amd64.deb\nSHA256: " + h("d") + "\n")
PY
m="$here/manifest.py"
"$m" generate --base "$w" --fedora 44 --arch x86_64 noarch --suite trixie > "$w/manifest"
for want in 'reac-pw-1.0.10-1.fc44.x86_64.rpm' 'reac-pw-1.0.11-1.fc44.x86_64.rpm' 'reac-pw-devel-1.0.11-1.fc44.noarch.rpm' 'libreac7_1.11.0_amd64.deb' 'libreac7_1.10.0_amd64.deb'; do
    grep -q " $want " "$w/manifest" || { echo "FAIL: generate dropped $want"; exit 1; }
done
if grep -qE 'reac-pw-1.0.9-|libreac7_1.9.0|other-thing' "$w/manifest"; then echo "FAIL: generate kept a third version or a package that is not FreeREAC's"; exit 1; fi
"$m" verify --base "$w" "$w/manifest" > /dev/null || { echo "FAIL: a manifest generated from the channel was refused"; exit 1; }
# the stale line: the noarch rpm listed under the x86_64 tree, where the index does not list it
sed 's|rpm/fedora/44/noarch|rpm/fedora/44/x86_64|' "$w/manifest" > "$w/stale"
if out=$("$m" verify --base "$w" "$w/stale" 2>&1); then echo "FAIL: a stale manifest line was accepted"; exit 1; fi
grep -q 'rpm/fedora/44/x86_64/reac-pw-devel-1.0.11-1.fc44.noarch.rpm: the channel.s index does not list it there' <<< "$out" || { echo "FAIL: the refusal does not name the line: $out"; exit 1; }
sed 's|\(libreac7_1.11.0_amd64.deb \).*|\1'"$(printf 'e%.0s' $(seq 64))"'|' "$w/manifest" > "$w/badsha"
if out=$("$m" verify --base "$w" "$w/badsha" 2>&1); then echo "FAIL: a wrong sha256 was accepted"; exit 1; fi
grep -q 'libreac7_1.11.0_amd64.deb: the index states sha256' <<< "$out" || { echo "FAIL: the sha refusal does not name the file: $out"; exit 1; }
if "$m" verify --base "$w/nowhere" "$w/manifest" > /dev/null 2>&1; then echo "FAIL: an unreadable index passed"; exit 1; fi
echo "manifest: ok"
