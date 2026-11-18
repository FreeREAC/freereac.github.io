#!/bin/bash
# The channel keeps the newest 2 versions of each package in each tree. Fails, naming the package and the tree, above 2.
#
#   check-newest-two.sh manifest import/manifest.txt     the files an import manifest lists
#   check-newest-two.sh tree <channel root>              the rpm/ and deb/ trees of the channel
set -euo pipefail
mode=${1:?usage: check-newest-two.sh manifest <file> | tree <root>}
arg=${2:?usage: check-newest-two.sh manifest <file> | tree <root>}
list=$(mktemp); trap 'rm -f "$list"' EXIT
case $mode in
manifest) awk '$1 == "rpm" || $1 == "deb" {print $2, $3}' "$arg" > "$list" ;;
tree) (cd "$arg" && find $(ls -d rpm/fedora deb/debian 2>/dev/null) \( -name '*.rpm' -o -name '*.deb' \) ! -path '*/SRPMS/*' | sed 's|/\([^/]*\)$| \1|') > "$list" ;;
*) echo "unknown mode $mode" >&2; exit 2 ;;
esac
# <dir> <file> -> <dir> <package> <version>, one line per file; an rpm is name-version-release.dist.arch.rpm, a deb name_version_arch.deb
awk '{
  f = $2; d = $1
  if (f ~ /\.rpm$/) { n = f; sub(/\.rpm$/, "", n); sub(/\.[^.]+$/, "", n); sub(/\.fc[0-9]+$/, "", n)
    r = n; sub(/.*-/, "", r); sub(/-[^-]*$/, "", n); v = n; sub(/.*-/, "", v); sub(/-[^-]*$/, "", n); print d, n, v "-" r }
  else { split(f, p, "_"); print d, p[1], p[2] }
}' "$list" | sort -u | awk '{k = $1 " " $2; c[k]++} END {bad = 0; for (k in c) if (c[k] > 2) {print "FAIL: " k " has " c[k] " versions, the channel keeps the newest 2" > "/dev/stderr"; bad = 1} exit bad}'
echo "newest-2 ok ($mode)"
