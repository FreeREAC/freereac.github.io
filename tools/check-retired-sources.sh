#!/bin/bash
# No source rpm of a retired Fedora release is served, nor placed by an import (owner rulings 2026-11-19 and 2026-11-23:
# Fedora 44 is dropped; docs/design.md, #14). RETIRED_FEDORA (space separated, default 44) is the one place the list is
# written. Fails naming every file: a src.rpm or an SRPMS/ tree under rpm/fedora/<retired>/ of the channel root, and a
# manifest line for rpm/fedora/<retired>/SRPMS. The fc44 binaries are not this rule's.
#
#   check-retired-sources.sh <channel root> <manifest>
#   check-retired-sources.sh --self-test
set -euo pipefail
retired=${RETIRED_FEDORA:-44}

check() {
    local root=$1 manifest=$2 r bad=0 hit
    for r in $retired; do
        if [ -d "$root/rpm/fedora/$r/SRPMS" ]; then
            hit=$(cd "$root" && find "rpm/fedora/$r/SRPMS" -type f | sort)
            echo "FAIL: rpm/fedora/$r/SRPMS is served; Fedora $r is retired:" >&2
            printf '  %s\n' ${hit:-"(an empty tree)"} >&2
            bad=1
        fi
        hit=$(awk -v d="rpm/fedora/$r/SRPMS" '$1 == "rpm" && $2 == d {print $2 "/" $3}' "$manifest")
        if [ -n "$hit" ]; then
            echo "FAIL: the manifest places source rpms of retired Fedora $r:" >&2
            printf '  %s\n' $hit >&2
            bad=1
        fi
    done
    [ "$bad" = 0 ] && echo "retired-sources ok (retired: $retired)"
    return "$bad"
}

self_test() {
    local w; w=$(mktemp -d); trap 'rm -rf "$w"' RETURN
    mkdir -p "$w/rpm/fedora/45/SRPMS" "$w/rpm/fedora/44/x86_64"
    touch "$w/rpm/fedora/45/SRPMS/reac-pw-1-1.fc45.src.rpm" "$w/rpm/fedora/44/x86_64/reac-pw-1-1.fc44.x86_64.rpm"
    printf 'rpm rpm/fedora/45/SRPMS reac-pw-1-1.fc45.src.rpm aa\n' > "$w/m"
    check "$w" "$w/m" > /dev/null || { echo "FAIL self-test: a fc45 source and a fc44 binary were refused"; return 1; }
    mkdir -p "$w/rpm/fedora/44/SRPMS"; touch "$w/rpm/fedora/44/SRPMS/reac-pw-1-1.fc44.src.rpm"
    if check "$w" "$w/m" 2> /dev/null; then echo "FAIL self-test: a fc44 source rpm in the tree passed"; return 1; fi
    rm -rf "$w/rpm/fedora/44/SRPMS"
    printf 'rpm rpm/fedora/44/SRPMS reac-pw-1-1.fc44.src.rpm aa\n' >> "$w/m"
    if check "$w" "$w/m" 2> /dev/null; then echo "FAIL self-test: a fc44 source rpm in the manifest passed"; return 1; fi
    echo "retired-sources self-test ok"
}

case ${1:-} in
--self-test) self_test ;;
'') echo "usage: check-retired-sources.sh <channel root> <manifest> | --self-test" >&2; exit 2 ;;
*) check "$1" "${2:?manifest}" ;;
esac
