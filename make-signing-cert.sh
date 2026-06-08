#!/bin/bash
# Creates a self-signed code-signing certificate ("DinoDock Local Signing") in
# your login keychain, once. build.sh then signs with it so macOS keeps granted
# permissions (Accessibility, etc.) across rebuilds — instead of an ad-hoc
# signature that changes every build and makes you re-grant each time.
#
# This certificate is local-only: it is NOT trusted for distribution and only
# used to sign DinoDock on this Mac. Run once:  ./make-signing-cert.sh
set -e

NAME="DinoDock Local Signing"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"

if security find-certificate -c "$NAME" >/dev/null 2>&1; then
  echo "✅ '$NAME' already exists — nothing to do."
  exit 0
fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

echo "Creating self-signed code-signing certificate '$NAME' …"
openssl req -x509 -newkey rsa:2048 -nodes \
  -keyout "$TMP/key.pem" -out "$TMP/cert.pem" -days 3650 \
  -subj "/CN=$NAME" \
  -addext "basicConstraints=critical,CA:false" \
  -addext "keyUsage=critical,digitalSignature" \
  -addext "extendedKeyUsage=critical,codeSigning" >/dev/null 2>&1

# -legacy: macOS's importer can't read OpenSSL 3's default PKCS12 MAC algorithm.
openssl pkcs12 -export -legacy -out "$TMP/id.p12" \
  -inkey "$TMP/key.pem" -in "$TMP/cert.pem" \
  -name "$NAME" -passout pass:dino >/dev/null 2>&1

security import "$TMP/id.p12" -k "$KEYCHAIN" -P dino -T /usr/bin/codesign -A

echo "✅ Done. Now run ./build.sh — it will sign with '$NAME'."
echo "   Grant Accessibility to DinoDock once; it will persist across future builds."
