#!/bin/bash
# The public key files the channel serves each hold exactly ONE key, and it is the channel's: the fingerprint of the organisation
# variable FREEREAC_RELEASE_KEY_FPR, the one place that pins it. Refused by name otherwise.
#
#   check-channel-key.sh <fingerprint> <key file>...
set -euo pipefail
want=${1:-}
shift || true
[[ $want =~ ^[0-9A-Fa-f]{40}$ ]] || { echo "FAIL: '$want' is not a key fingerprint: the variable FREEREAC_RELEASE_KEY_FPR is unset or malformed" >&2; exit 1; }
[ "$#" -gt 0 ] || { echo "usage: check-channel-key.sh <fingerprint> <key file>..." >&2; exit 2; }
for f in "$@"; do
    have=$(gpg --batch --with-colons --import-options show-only --import < "$f" 2>/dev/null | awk -F: '/^pub:/ {p = 1; next} /^fpr:/ && p {print $10; p = 0}')
    [ "$(wc -w <<< "$have")" = 1 ] || { echo "FAIL: $f holds $(wc -w <<< "$have") keys ($(tr '\n' ' ' <<< "$have")), the channel serves exactly one" >&2; exit 1; }
    [ "${have^^}" = "${want^^}" ] || { echo "FAIL: $f holds $have, not the $want the channel signs with" >&2; exit 1; }
    echo "$f: $have"
done
