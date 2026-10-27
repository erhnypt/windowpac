#!/usr/bin/env bash
# One-time: creates a local self-signed code-signing identity "WindowPac Local" so the app keeps
# the same signature across rebuilds (macOS then keeps the Accessibility / Input Monitoring grants).
set -euo pipefail
NAME="WindowPac Local"
KC="$HOME/Library/Keychains/login.keychain-db"

if security find-identity -p codesigning "$KC" | grep -q "$NAME"; then
  echo "Identity '$NAME' already exists."; exit 0
fi

T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
cat > "$T/c.cnf" <<CNF
[req]
distinguished_name = dn
x509_extensions = ext
prompt = no
[dn]
CN = $NAME
[ext]
basicConstraints = critical,CA:false
keyUsage = critical,digitalSignature
extendedKeyUsage = critical,codeSigning
CNF
openssl req -x509 -newkey rsa:2048 -nodes -days 3650 -config "$T/c.cnf" \
  -keyout "$T/k.pem" -out "$T/c.pem" 2>/dev/null
openssl pkcs12 -export -inkey "$T/k.pem" -in "$T/c.pem" -out "$T/id.p12" -passout pass:windowpac

security import "$T/id.p12" -k "$KC" -P windowpac -T /usr/bin/codesign
# Trust it for code signing (macOS asks for your login password once).
security add-trusted-cert -d -r trustRoot -p codeSign -k "$KC" "$T/c.pem"
echo "Created identity '$NAME'."
