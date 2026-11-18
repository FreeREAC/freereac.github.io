#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 Pau Aliagas <linuxnow@gmail.com>
# build.sh refuses an unset fingerprint, a key that is not the channel's, and a file with two keys; it builds with the one key.
set -euo pipefail
here=$(dirname "$(readlink -f "$0")"); w=$(mktemp -d); export GNUPGHOME=$w/g; mkdir -m700 "$GNUPGHOME"
for n in a b; do gpg --batch -q --passphrase '' --quick-gen-key "Key $n <$n@example.org>" ed25519 sign 1y; done
fpr() { gpg --with-colons --fingerprint "$1@example.org" | awk -F: '/^fpr:/ {print $10; exit}'; }
A=$(fpr a); B=$(fpr b)
gpg --batch --armor --export "$A" > "$w/one.asc"; gpg --batch --armor --export "$A" "$B" > "$w/two.asc"
if FREEREAC_RELEASE_KEY_FPR= "$here/build.sh" rpm "$w/one.asc" "$w/o" 2>/dev/null; then echo "FAIL: an unset fingerprint built"; exit 1; fi
if FREEREAC_RELEASE_KEY_FPR=UNSET "$here/build.sh" rpm "$w/one.asc" "$w/o" 2>/dev/null; then echo "FAIL: a placeholder built"; exit 1; fi
if out=$(FREEREAC_RELEASE_KEY_FPR=$B "$here/build.sh" rpm "$w/one.asc" "$w/o" 2>&1); then echo "FAIL: another key built"; exit 1; fi
grep -q "not the $B" <<< "$out" || { echo "FAIL: the refusal does not name the key: $out"; exit 1; }
if out=$(FREEREAC_RELEASE_KEY_FPR=$A "$here/build.sh" rpm "$w/two.asc" "$w/o" 2>&1); then echo "FAIL: a two-key file built"; exit 1; fi
grep -q 'holds 2 keys' <<< "$out" || { echo "FAIL: the two-key refusal does not say so: $out"; exit 1; }
FREEREAC_RELEASE_KEY_FPR=$A "$here/build.sh" ${KIND:-rpm} "$w/one.asc" "$w/o" >/dev/null
echo "freereac-release build: ok"
