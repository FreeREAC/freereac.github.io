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

# copy every <ext> file of <src> into <dest>, or fail by name: an empty directory is refused (the manifest put it there), and a copy that
# fails (unreadable file, full disk, permission) stops the run, so a tree missing packages is never published
copy_all() {
    local src=$1 dest=$2 ext=$3 files
    shopt -s nullglob
    files=("$src"/*."$ext")
    shopt -u nullglob
    [ "${#files[@]}" -gt 0 ] || { echo "FAIL: $src holds no .$ext file to place, though the manifest listed it" >&2; return 1; }
    mkdir -p "$dest"
    local f keep=()
    for f in "${files[@]}"; do
        # a published deb is immutable: one already in the tree is kept, named; the rest are copied and any failure stops the run
        if [ "$ext" = deb ] && [ -e "$dest/$(basename "$f")" ]; then echo "kept $dest/$(basename "$f"): already published"; else keep+=("$f"); fi
    done
    [ "${#keep[@]}" -eq 0 ] || cp -- "${keep[@]}" "$dest/"
}

place() {
    local dir=$1 root=$2 key=$3 d f p kind
    export GPG_TTY=
    # a package already in the tree that the channel key does not vouch for (signed by a retired key) leaves: a channel serves what its
    # one key signed, and a client holding only that key would refuse the file
    local ks; ks=$(mktemp -d); gpg --batch --armor --export "$key" > "$ks/k.asc"; rpmkeys --root "$ks" --import "$ks/k.asc"
    while IFS= read -r p; do
        rpmkeys --root "$ks" --checksig "$p" 2>/dev/null | grep -q 'digests signatures OK' || { echo "dropped $p: not signed by the channel key"; rm -f "$p"; }
    done < <(find "$root/rpm/fedora" -name '*.rpm' 2>/dev/null)
    # The channel has two dnf trees, both read by the repository file (freereac: fedora/<release>/$basearch, freereac-noarch:
    # fedora/<release>/noarch). The architecture directories hold what THIS import places, so a noarch package of the OpenMixer channel's
    # noarch tree is placed INSIDE each architecture directory of its release; the noarch/ tree holds what the shared publish places there
    # (freereac-release, and future noarch releases per the release matrix) and the import never writes it.
    for d in $(cd "$dir" && find rpm -type d -path 'rpm/fedora/*/*' | sort); do
        for f in "$dir/$d"/*.rpm; do
            [ -e "$f" ] || continue
            # the payload and header are untouched; only the signature header is replaced
            rpmsign --delsign "$f" >/dev/null
            rpmsign --addsign --define "_gpg_name $key" --define "_gpg_sign_cmd_extra_args --pinentry-mode loopback" "$f" >/dev/null
        done
        if [ "$(basename "$d")" = noarch ]; then
            local rel=${d%/noarch} targets
            targets=$( { (cd "$dir" && find "$rel" -mindepth 1 -maxdepth 1 -type d ! -name noarch ! -name SRPMS); (cd "$root" 2>/dev/null && find "$rel" -mindepth 1 -maxdepth 1 -type d ! -name noarch ! -name SRPMS) || true; } 2>/dev/null | sort -u)
            [ -n "$targets" ] || { echo "no architecture directory of $rel to place the noarch packages in" >&2; exit 1; }
            for t in $targets; do copy_all "$dir/$d" "$root/$t" rpm; done
        else
            copy_all "$dir/$d" "$root/$d" rpm
        fi
    done
    for d in $([ -d "$dir/deb" ] && cd "$dir" && find deb -type d -path 'deb/debian/*/*' | sort); do
        copy_all "$dir/$d" "$root/$d" deb
    done
    "$(dirname "$(readlink -f "$0")")/prune-newest-two.sh" "$root"
    for d in $(cd "$root" && find rpm/fedora -mindepth 2 -maxdepth 2 -type d ! -name SRPMS | sort); do
        createrepo_c --quiet --general-compress-type=gz "$root/$d"
        gpg --batch --yes --pinentry-mode loopback --armor --detach-sign -u "$key" --output "$root/$d/repodata/repomd.xml.asc" "$root/$d/repodata/repomd.xml"
    done
    for suite in $([ -d "$root/deb/debian" ] && ls "$root/deb/debian"); do
        (cd "$root/deb/debian/$suite"
         # one flat index of the suite: Filename is ./<arch>/<file>, and apt takes the packages of its own architecture
         apt-ftparchive packages . > Packages && gzip -kf9 Packages
         apt-ftparchive -o APT::FTPArchive::Release::Origin=FreeREAC -o APT::FTPArchive::Release::Label=FreeREAC release . > Release
         gpg --batch --yes --pinentry-mode loopback --armor --detach-sign -u "$key" --output Release.gpg Release
         gpg --batch --yes --pinentry-mode loopback --clearsign -u "$key" --output InRelease Release)
    done
    gpg --batch --armor --export "$key" > "$root/rpm/RPM-GPG-KEY-freereac"
    if [ -d "$root/deb" ]; then gpg --batch --armor --export "$key" > "$root/deb/freereac.asc"; fi
}

case $cmd in
fetch) fetch "${2:?manifest}" "${3:?dir}" ;;
place) place "${2:?dir}" "${3:?root}" "${4:?key}" ;;
*) echo "unknown command $cmd" >&2; exit 2 ;;
esac
