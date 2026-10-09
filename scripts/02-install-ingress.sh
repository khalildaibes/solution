#!/usr/bin/env bash
# Install ingress-nginx (kind flavour: hostPort 80/443 on the ingress-ready node) and wait for it.
set -euo pipefail
cd "$(dirname "$0")/.."
kubectl --context kind-thetaray apply -f cluster/ingress-nginx-kind.yaml
kubectl --context kind-thetaray wait --namespace ingress-nginx \
  --for=condition=ready pod --selector=app.kubernetes.io/component=controller --timeout=180s
kubectl --context kind-thetaray -n ingress-nginx get pods
