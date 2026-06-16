#!/usr/bin/env bash
# Create a stable self-signed code-signing certificate in the login keychain so
# local Debug builds keep a constant code identity — letting a one-time Keychain
# "Always Allow" persist across rebuilds instead of re-prompting every build.
#
# Usage:  ./scripts/create-signing-cert.sh ["CrossPost Local"]
# Then:   cp Local.xcconfig.example Local.xcconfig   (name must match)
#         ./build.sh && open build/CrossPost.app     (click "Always Allow" once)
set -euo pipefail

name="${1:-CrossPost Local}"
keychain="$HOME/Library/Keychains/login.keychain-db"

if security find-identity -p codesigning "$keychain" | grep -qF "\"$name\""; then
  echo "A code-signing identity named '$name' already exists. Nothing to do."
  exit 0
fi

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

cat >"$tmp/cert.conf" <<EOF
[req]
distinguished_name = dn
x509_extensions    = ext
prompt             = no
[dn]
CN = $name
[ext]
basicConstraints     = critical,CA:false
keyUsage             = critical,digitalSignature
extendedKeyUsage     = critical,codeSigning
EOF

openssl req -x509 -newkey rsa:2048 -nodes -days 3650 \
  -keyout "$tmp/cert.key" -out "$tmp/cert.crt" -config "$tmp/cert.conf"
openssl pkcs12 -export -inkey "$tmp/cert.key" -in "$tmp/cert.crt" \
  -name "$name" -out "$tmp/cert.p12" -passout pass:

# Import the cert + key; -T scopes key access to codesign (first build may prompt
# once to allow it — click "Always Allow").
security import "$tmp/cert.p12" -k "$keychain" -P "" -T /usr/bin/codesign

echo
echo "Created code-signing identity '$name'. Verify with:"
echo "  security find-identity -v -p codesigning"
echo "Next: cp Local.xcconfig.example Local.xcconfig  (CODE_SIGN_IDENTITY must equal '$name')"
