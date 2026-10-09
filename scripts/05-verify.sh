#!/usr/bin/env bash
# End-to-end check through the ingress controller, over HTTP and HTTPS.
# --resolve avoids depending on the hosts file; drop it once "127.0.0.1 http-echo.k8s-server.local" is mapped.
set -euo pipefail
cd "$(dirname "$0")/.."
HOST="${HOST:-http-echo.k8s-server.local}"
IP="${IP:-127.0.0.1}"
# curl built on Windows Schannel cannot check revocation for a private CA (no CRL/OCSP) and fails
# with "revocation status is unknown". Chain + hostname are still verified; only the CRL lookup is skipped.
REVOKE=""; curl --version | grep -qi schannel && REVOKE="--ssl-no-revoke"
echo "== HTTP =="
curl -sS --fail --resolve "$HOST:80:$IP"  "http://$HOST/"  | head -c 400; echo
echo "== HTTPS (verified against the local CA) =="
curl -sS --fail $REVOKE --resolve "$HOST:443:$IP" --cacert tls/ca.crt "https://$HOST/" | head -c 400; echo
echo "== HTTPS without the CA must be rejected (proves verification is real) =="
if curl -sS $REVOKE --resolve "$HOST:443:$IP" "https://$HOST/" -o /dev/null 2>/dev/null; then echo "UNEXPECTED: accepted untrusted cert"; exit 1; else echo "rejected as expected"; fi
echo "== certificate presented by the ingress =="
openssl s_client -connect "$IP:443" -servername "$HOST" </dev/null 2>/dev/null | openssl x509 -noout -subject -issuer -ext subjectAltName -dates
