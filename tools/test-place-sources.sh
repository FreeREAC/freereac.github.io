#!/bin/bash
# A source rpm moved by the import is served: import.sh place re-signs it with the channel key, copies it into SRPMS/ of its release and
# writes that tree's signed repodata, so the repository file's freereac-source repository lists it. Without the repodata the file sits in the
# tree and dnf sees an empty index (FreeREAC/freereac.github.io#12). Fedora container with rpm-build, rpm-sign, createrepo_c, apt-utils,
# gnupg2, pinentry.
set -euo pipefail
here=$(dirname "$(readlink -f "$0")"); w=$(mktemp -d); export GNUPGHOME=$w/g; mkdir -m700 "$GNUPGHOME"
gpg --batch -q --passphrase '' --quick-gen-key 'T <t@example.org>' rsa3072 sign 1y
K=$(gpg --with-colons --fingerprint t@example.org | awk -F: '/^fpr:/ {print $10; exit}')
printf 'Name: pkg-src\nVersion: 1\nRelease: 1.fc44\nSummary: t\nLicense: MIT\n%%description\nt\n%%files\n' > "$w/pkg-src.spec"
rpmbuild -bs --quiet --define "_topdir $w/rb" "$w/pkg-src.spec" >/dev/null 2>&1
mkdir -p "$w/dl/rpm/fedora/44/SRPMS"; cp "$w/rb/SRPMS/pkg-src-1-1.fc44.src.rpm" "$w/dl/rpm/fedora/44/SRPMS/"
"$here/import.sh" place "$w/dl" "$w/root" "$K" > "$w/place.log" 2>&1 || { tail -8 "$w/place.log" >&2; echo "FAIL: place failed"; exit 1; }
s=$w/root/rpm/fedora/44/SRPMS
[ -e "$s/pkg-src-1-1.fc44.src.rpm" ] || { echo "FAIL: the source rpm is not in SRPMS/"; exit 1; }
[ -e "$s/repodata/repomd.xml" ] || { echo "FAIL: SRPMS/ has no repodata: the source repository serves nothing"; exit 1; }
gpg --batch -q --verify "$s/repodata/repomd.xml.asc" "$s/repodata/repomd.xml" 2>/dev/null || { echo "FAIL: the SRPMS/ metadata is not signed by the channel key"; exit 1; }
gpg --armor --export "$K" > "$w/k.asc"; rpmkeys --import "$w/k.asc"
rpm -K "$s/pkg-src-1-1.fc44.src.rpm" | grep -q 'signatures OK' || { echo "FAIL: the source rpm is not signed by the channel key"; exit 1; }
got=$(dnf -y -q --disablerepo='*' --repofrompath="t,file://$s" --setopt=t.gpgcheck=1 --setopt=t.repo_gpgcheck=1 --setopt="t.gpgkey=file://$w/k.asc" \
      repoquery --qf '%{name}-%{version}-%{release}.%{arch}\n' 2>/dev/null)
grep -qx 'pkg-src-1-1.fc44.src' <<< "$got" || { echo "FAIL: the source repository does not list pkg-src: '$got'"; exit 1; }
echo "place-sources: ok"
