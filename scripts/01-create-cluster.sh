#!/usr/bin/env bash
# Create the local kind cluster (idempotent).
set -euo pipefail
cd "$(dirname "$0")/.."
if kind get clusters 2>/dev/null | grep -qx thetaray; then
  echo "kind cluster thetaray already exists - skipping"
else
  kind create cluster --config cluster/kind-config.yaml --wait 120s
fi
kubectl --context kind-thetaray get nodes -o wide
