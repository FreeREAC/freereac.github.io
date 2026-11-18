#!/bin/bash
# check-channel-key refuses an unset fingerprint, another key, a file with two keys, and passes the channel's one key.
set -euo pipefail
here=$(dirname "$(readlink -f "$0")"); w=$(mktemp -d); export GNUPGHOME=$w/g; mkdir -m700 "$GNUPGHOME"
for n in a b; do gpg --batch -q --passphrase '' --quick-gen-key "K $n <$n@example.org>" ed25519 sign 1y; done
fpr() { gpg --with-colons --fingerprint "$1@example.org" | awk -F: '/^fpr:/ {print $10; exit}'; }
A=$(fpr a); B=$(fpr b)
gpg --batch --armor --export "$A" > "$w/one.asc"; gpg --batch --armor --export "$A" "$B" > "$w/two.asc"
"$here/check-channel-key.sh" "$A" "$w/one.asc" > /dev/null || { echo "FAIL: the channel's key was refused"; exit 1; }
if "$here/check-channel-key.sh" "" "$w/one.asc" 2>/dev/null; then echo "FAIL: an unset fingerprint passed"; exit 1; fi
if out=$("$here/check-channel-key.sh" "$B" "$w/one.asc" 2>&1); then echo "FAIL: another key passed"; exit 1; fi
grep -q "not the $B" <<< "$out" || { echo "FAIL: the refusal does not name the key: $out"; exit 1; }
if out=$("$here/check-channel-key.sh" "$A" "$w/two.asc" 2>&1); then echo "FAIL: a two-key file passed"; exit 1; fi
grep -q 'holds 2 keys' <<< "$out" || { echo "FAIL: the two-key refusal does not say so: $out"; exit 1; }
echo "check-channel-key: ok"
