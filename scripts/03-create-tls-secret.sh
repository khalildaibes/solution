#!/usr/bin/env bash
# Generate a local CA + server certificate for http-echo.k8s-server.local and store it as the
# kubernetes.io/tls secret referenced by the chart (ingress.tls[0].secretName).
# Production note: replace this with cert-manager (Issuer + Certificate) or an imported CA-signed cert.
set -euo pipefail
cd "$(dirname "$0")/.."
HOST="${HOST:-http-echo.k8s-server.local}"
NS="${NS:-http-echo}"
SECRET="${SECRET:-http-echo-tls}"
OUT="tls"; mkdir -p "$OUT"
export MSYS_NO_PATHCONV=1   # Git Bash: stop /CN=... from being rewritten as a Windows path

if [[ ! -f "$OUT/ca.crt" ]]; then
  openssl req -x509 -newkey rsa:2048 -sha256 -nodes -days 3650 \
    -subj "/CN=http-echo local CA" -keyout "$OUT/ca.key" -out "$OUT/ca.crt" \
    -addext "basicConstraints=critical,CA:TRUE" -addext "keyUsage=critical,keyCertSign,cRLSign"
fi
openssl req -newkey rsa:2048 -sha256 -nodes -subj "/CN=$HOST" \
  -keyout "$OUT/tls.key" -out "$OUT/tls.csr" -addext "subjectAltName=DNS:$HOST"
printf 'subjectAltName=DNS:%s\nextendedKeyUsage=serverAuth\nkeyUsage=critical,digitalSignature,keyEncipherment\nbasicConstraints=CA:FALSE\n' "$HOST" > "$OUT/server.ext"
openssl x509 -req -sha256 -days 365 -in "$OUT/tls.csr" -CA "$OUT/ca.crt" -CAkey "$OUT/ca.key" \
  -CAcreateserial -extfile "$OUT/server.ext" -out "$OUT/tls.crt"

kubectl --context kind-thetaray create namespace "$NS" --dry-run=client -o yaml | kubectl --context kind-thetaray apply -f -
kubectl --context kind-thetaray -n "$NS" create secret tls "$SECRET" \
  --cert="$OUT/tls.crt" --key="$OUT/tls.key" --dry-run=client -o yaml | kubectl --context kind-thetaray apply -f -
echo "secret $NS/$SECRET created. CA for curl --cacert: $OUT/ca.crt"
