#!/usr/bin/env bash
# Lint, deploy (install or upgrade) and run the chart connectivity test.
set -euo pipefail
cd "$(dirname "$0")/.."
HELM="${HELM:-helm}"
"$HELM" lint http-echo
"$HELM" upgrade --install http-echo ./http-echo \
  --namespace http-echo --create-namespace --kube-context kind-thetaray \
  --wait --timeout 120s
"$HELM" test http-echo --namespace http-echo --kube-context kind-thetaray
kubectl --context kind-thetaray -n http-echo get pods,svc,ingress -o wide
