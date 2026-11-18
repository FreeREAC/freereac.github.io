#!/bin/bash
# Move released packages from the OpenMixer channel into this channel (docs/design.md). Runs in CI, in a Fedora container
# with rpm-sign, createrepo_c, apt-utils, gnupg2 and git; the signing key is imported by the workflow, never by hand.
#
#   import.sh fetch <manifest> <dir>     download each listed file and verify it against the manifest checksum and, for an rpm, its
#                                        current OpenMixer signature, for a deb its entry in the OpenMixer Packages index
#   import.sh place <dir> <root> <key>   re-sign the rpm signature headers with <key>, copy the debs as they are, regenerate and sign
#                                        the rpm repodata and the deb index, serve <key>'s public half, keep the newest 2
set -euo pipefail
BASE=${BASE_URL:-https://www.openmixer.org}
cmd=${1:?usage: import.sh fetch|place ...}
curl_() { curl -fsSL --retry 5 --retry-all-errors --retry-delay 3 --connect-timeout 20 "$@"; }

fetch() {
    local manifest=$1 dir=$2 kind d f sum got home
    mkdir -p "$dir"
    home=$(mktemp -d)
    curl_ "$BASE/rpm/RPM-GPG-KEY-openmixer" -o "$home/om.asc"
    mkdir "$home/root"
    # rpmkeys takes one key per file
    GNUPGHOME=$home gpg --batch --quiet --import "$home/om.asc" 2>/dev/null
    for fpr in $(GNUPGHOME=$home gpg --batch --with-colons --fingerprint | awk -F: '/^pub:/ {p = 1; next} /^fpr:/ && p {print $10; p = 0}'); do
        GNUPGHOME=$home gpg --batch --armor --export "$fpr" > "$home/k.asc"; rpmkeys --root "$home/root" --import "$home/k.asc"
    done
    declare -A idx=()
    while read -r kind d f sum; do
        case $kind in '' | '#'*) continue ;; esac
        mkdir -p "$dir/$d"
        curl_ "$BASE/$d/$f" -o "$dir/$d/$f"
        got=$(sha256sum < "$dir/$d/$f" | cut -d' ' -f1)
        [ "$got" = "$sum" ] || { echo "FAIL: $f has sha256 $got, the manifest says $sum" >&2; exit 1; }
        if [ "$kind" = rpm ]; then
            rpmkeys --root "$home/root" --checksig "$dir/$d/$f" | grep -q 'digests signatures OK' ||
                { echo "FAIL: $f has no good OpenMixer signature" >&2; exit 1; }
        else
            # deb/debian/trixie/<arch>: the Packages index the OpenMixer InRelease covers must list this file with this sha256
            local suite=${d#deb/debian/} ; suite=${suite%%/*}
            [ -n "${idx[$suite]:-}" ] || { idx[$suite]=$(mktemp); curl_ "$BASE/deb/debian/$suite/Packages" -o "${idx[$suite]}"; }
            grep -q "^SHA256: $sum\$" "${idx[$suite]}" || { echo "FAIL: $f is not in the OpenMixer $suite index with sha256 $sum" >&2; exit 1; }
        fi
        echo "verified $d/$f"
    done < "$manifest"
}

place() {
    local dir=$1 root=$2 key=$3 d f p kind
    export GPG_TTY=
    for d in $(cd "$dir" && find rpm -type d -path 'rpm/fedora/*/*' | sort); do
        mkdir -p "$root/$d"
        for f in "$dir/$d"/*.rpm; do
            [ -e "$f" ] || continue
            # the payload and header are untouched; only the signature header is replaced
            rpmsign --delsign "$f" >/dev/null
            rpmsign --addsign --define "_gpg_name $key" --define "_gpg_sign_cmd_extra_args --pinentry-mode loopback" "$f" >/dev/null
            cp "$f" "$root/$d/"
        done
    done
    for d in $(cd "$dir" && find deb -type d -path 'deb/debian/*/*' | sort); do
        mkdir -p "$root/$d"; cp -n "$dir/$d"/*.deb "$root/$d/" 2>/dev/null || true
    done
    "$(dirname "$(readlink -f "$0")")/prune-newest-two.sh" "$root"
    for d in $(cd "$root" && find rpm/fedora -mindepth 2 -maxdepth 2 -type d ! -name SRPMS | sort); do
        createrepo_c --quiet --general-compress-type=gz "$root/$d"
        gpg --batch --yes --pinentry-mode loopback --armor --detach-sign -u "$key" --output "$root/$d/repodata/repomd.xml.asc" "$root/$d/repodata/repomd.xml"
    done
    for suite in $(cd "$root" && ls deb/debian 2>/dev/null); do
        (cd "$root/deb/debian/$suite"
         # one flat index of the suite: Filename is ./<arch>/<file>, and apt takes the packages of its own architecture
         apt-ftparchive packages . > Packages && gzip -kf9 Packages
         apt-ftparchive -o APT::FTPArchive::Release::Origin=FreeREAC -o APT::FTPArchive::Release::Label=FreeREAC release . > Release
         gpg --batch --yes --pinentry-mode loopback --armor --detach-sign -u "$key" --output Release.gpg Release
         gpg --batch --yes --pinentry-mode loopback --clearsign -u "$key" --output InRelease Release)
    done
    gpg --batch --armor --export "$key" > "$root/rpm/RPM-GPG-KEY-freereac"
    gpg --batch --armor --export "$key" > "$root/deb/freereac.asc"
}

case $cmd in
fetch) fetch "${2:?manifest}" "${3:?dir}" ;;
place) place "${2:?dir}" "${3:?root}" "${4:?key}" ;;
*) echo "unknown command $cmd" >&2; exit 2 ;;
esac
