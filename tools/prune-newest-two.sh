#!/bin/bash
# Keep the newest 2 versions of each package in each tree of the channel root; older files are removed.
set -euo pipefail
root=${1:?usage: prune-newest-two.sh <channel root>}
cd "$root"
# per directory, per package: list distinct versions, drop all but the 2 newest (a version may be one file)
find rpm/fedora deb/debian \( -name '*.rpm' -o -name '*.deb' \) ! -path '*/SRPMS/*' | while read -r path; do
    dir=$(dirname "$path"); f=$(basename "$path")
    if [[ $f == *.rpm ]]; then n=${f%.rpm}; n=${n%.*}; n=${n%.fc[0-9]*}; r=${n##*-}; n=${n%-*}; v=${n##*-}-$r; n=${n%-*}
    else IFS=_ read -r n v _ <<< "${f%.deb}"; fi
    printf '%s\t%s\t%s\t%s\n' "$dir" "$n" "$v" "$path"
done | sort -t$'\t' -k1,2 -k3,3V | awk -F'\t' '
    { k = $1 SUBSEP $2; if (!(k $3 in seen)) { seen[k $3] = 1; ord[k] = ord[k] " " $3; cnt[k]++ } row[NR] = $0 }
    END { for (i = 1; i <= NR; i++) { split(row[i], x, "\t"); k = x[1] SUBSEP x[2]
        n = split(ord[k], vs, " "); keep = 0; for (j = n; j > n - 2 && j >= 1; j--) if (vs[j] == x[3]) keep = 1
        if (!keep) print x[4] } }' | while read -r gone; do echo "pruned $gone"; rm -f "$gone"; done
