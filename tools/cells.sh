#!/bin/bash
# Write or check rpm/cells.tsv with the channel's one implementation: release-matrix/cells.sh of the shared
# publish tooling, the same script that writes the index of the OpenMixer channel.
#   tools/cells.sh write   regenerate rpm/cells.tsv from the tree
#   tools/cells.sh check   fail when repodata exists but cells.tsv is missing or differs from the tree
# CELLS_SH may name a local copy of the script; otherwise it is fetched from the pinned ref.
set -euo pipefail
mode=${1:?usage: tools/cells.sh write|check}
root=$(cd "$(dirname "$0")/.." && pwd)
tree=$root/rpm
ref=${CELLS_REF:-openmixer-v1}
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
cells=${CELLS_SH:-}
if [ -z "$cells" ]; then
    cells=$tmp/cells.sh
    curl -fsSL "https://raw.githubusercontent.com/Open-Mixer/.github/$ref/.github/actions/release-matrix/cells.sh" -o "$cells"
fi
case $mode in
write) bash "$cells" rpm "$tree" ;;
check)
    ls "$tree"/fedora/*/*/repodata >/dev/null 2>&1 || { echo "no repodata: nothing to index"; exit 0; }
    [ -f "$tree/cells.tsv" ] || { echo "rpm/cells.tsv is missing although the tree has repodata: run tools/cells.sh write" >&2; exit 1; }
    mkdir "$tmp/t"; cp "$tree/cells.tsv" "$tmp/t/cells.tsv"
    # cells.sh reads file names only: mirror the names as empty files, so the check never copies a package
    (cd "$tree" && find fedora -type f -name "*.rpm") | while IFS= read -r f; do mkdir -p "$tmp/t/$(dirname "$f")"; : > "$tmp/t/$f"; done
    bash "$cells" rpm "$tmp/t" >/dev/null
    cmp -s "$tmp/t/cells.tsv" "$tree/cells.tsv" || { echo "rpm/cells.tsv is stale against the tree:" >&2; diff "$tree/cells.tsv" "$tmp/t/cells.tsv" >&2 || true; exit 1; }
    echo "rpm/cells.tsv matches the tree" ;;
*) echo "write or check" >&2; exit 2 ;;
esac
