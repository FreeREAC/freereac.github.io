#!/bin/bash
# The channel has two dnf trees, both read (freereac: architecture directories, freereac-noarch: noarch/). The architecture directories hold
# what the IMPORT places; the noarch/ tree holds what the shared publish places (freereac-release, future noarch releases) and the import never
# writes it. So import.sh place puts a noarch rpm of the OpenMixer channel's noarch tree inside EVERY architecture directory of its release,
# writes no noarch/ tree, signs it with the channel key, and dnf installs it from the architecture repository alone. Fedora container with
# rpm-build, rpm-sign, createrepo_c, apt-utils, gnupg2, pinentry.
set -euo pipefail
here=$(dirname "$(readlink -f "$0")"); w=$(mktemp -d); export GNUPGHOME=$w/g; mkdir -m700 "$GNUPGHOME"
gpg --batch -q --passphrase '' --quick-gen-key 'T <t@example.org>' rsa3072 sign 1y
K=$(gpg --with-colons --fingerprint t@example.org | awk -F: '/^fpr:/ {print $10; exit}')
spec() { printf 'Name: %s\nVersion: 1\nRelease: 1.fc44\nSummary: t\nLicense: MIT\nBuildArch: noarch\n%%description\nt\n%%files\n' "$1" > "$w/$1.spec"
         rpmbuild -bb --quiet --define "_topdir $w/rb" "$w/$1.spec" >/dev/null 2>&1; cp "$w/rb/RPMS/noarch/$1-1-1.fc44.noarch.rpm" "$2/"; }
for d in noarch x86_64 aarch64; do mkdir -p "$w/dl/rpm/fedora/44/$d"; done
spec pkg-devel "$w/dl/rpm/fedora/44/noarch"; spec pkg-arch "$w/dl/rpm/fedora/44/x86_64"; spec pkg-arch2 "$w/dl/rpm/fedora/44/aarch64"
"$here/import.sh" place "$w/dl" "$w/root" "$K" > "$w/place.log" 2>&1 || { tail -8 "$w/place.log" >&2; echo "FAIL: place failed"; exit 1; }
for a in x86_64 aarch64; do
    [ -e "$w/root/rpm/fedora/44/$a/pkg-devel-1-1.fc44.noarch.rpm" ] || { echo "FAIL: the noarch package is not inside $a"; exit 1; }
    [ -e "$w/root/rpm/fedora/44/$a/repodata/repomd.xml.asc" ] || { echo "FAIL: $a has no signed metadata"; exit 1; }
done
[ ! -e "$w/root/rpm/fedora/44/noarch" ] || { echo "FAIL: the import wrote the noarch/ tree, which only the shared publish writes"; exit 1; }
gpg --armor --export "$K" > "$w/k.asc"; rpmkeys --import "$w/k.asc"
rpm -K "$w/root/rpm/fedora/44/x86_64/pkg-devel-1-1.fc44.noarch.rpm" | grep -q 'signatures OK' || { echo "FAIL: the noarch package is not signed by the channel key"; exit 1; }
printf '[t]\nname=t\nbaseurl=file://%s/rpm/fedora/44/$basearch/\ngpgcheck=1\nrepo_gpgcheck=1\ngpgkey=file://%s\n' "$w/root" "$w/k.asc" > /etc/yum.repos.d/t.repo
dnf -y -q --disablerepo='*' --enablerepo=t --forcearch=x86_64 install pkg-devel > /dev/null 2>&1 || { echo "FAIL: dnf cannot install the noarch package from the architecture repository"; exit 1; }
rpm -q pkg-devel > /dev/null
# a copy that fails stops the run (a cp that fails, in the PATH: the tree is never published without its packages), and a directory with no
# package is refused by name
mkdir "$w/shim"; printf '#!/bin/sh\nexit 1\n' > "$w/shim/cp"; chmod +x "$w/shim/cp"
if out=$(PATH="$w/shim:$PATH" "$here/import.sh" place "$w/dl" "$w/root-cpfail" "$K" 2>&1); then echo "FAIL: a failed copy was swallowed"; exit 1; fi
mkdir -p "$w/dl-empty/rpm/fedora/44/x86_64"
if out=$("$here/import.sh" place "$w/dl-empty" "$w/root-empty" "$K" 2>&1); then echo "FAIL: an empty directory was placed silently"; exit 1; fi
grep -q 'rpm/fedora/44/x86_64 holds no .rpm file to place' <<< "$out" || { echo "FAIL: the empty directory is not named: $out"; exit 1; }
echo "place-noarch: ok"
