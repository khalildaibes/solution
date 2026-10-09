# http-echo on Kubernetes - ThetaRay DevOps assignment

Fixed Helm chart for `ealen/echo-server`, deployed on a local kind cluster behind ingress-nginx with TLS.

Full write-up (diagnosis, every fix with its reason, verification evidence, chronological action log,
production notes): **[SOLUTION.md](SOLUTION.md)**.

## Quick start

```bash
git checkout feature/http-echo-fix-and-tls
scripts/01-create-cluster.sh      # kind cluster, ports 80/443 on localhost
scripts/02-install-ingress.sh     # ingress-nginx
scripts/03-create-tls-secret.sh   # local CA + cert -> Secret http-echo/http-echo-tls
scripts/04-deploy.sh              # helm lint, upgrade --install, helm test
scripts/05-verify.sh              # curl over HTTP and HTTPS through the ingress
```

Then add `127.0.0.1 http-echo.k8s-server.local` to your hosts file and open
http://http-echo.k8s-server.local/ or https://http-echo.k8s-server.local/ (CA: `tls/ca.crt`).

## Branches

| Branch | Content |
|--------|---------|
| `main` | The chart exactly as received, only moved into standard Helm layout (baseline, broken) |
| `feature/http-echo-fix-and-tls` | The fix, TLS, cluster config, scripts and documentation |

`git diff main..feature/http-echo-fix-and-tls -- http-echo/` shows every chart change.
