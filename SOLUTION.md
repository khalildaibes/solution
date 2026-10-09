# ThetaRay DevOps Home Assignment - Solution & Process Log

Candidate: Khalil Daibes  
Date: 2026-10-09  
Submission branch: `feature/http-echo-fix-and-tls` (baseline of the chart as received is on `main`)

| Step | Requirement | Status |
|------|-------------|--------|
| 1 | Local Kubernetes cluster + ingress controller + Helm, deploy the chart | Done (kind + ingress-nginx + Helm 4) |
| 2 | Find why the chart is broken and fix the environment | Done - 5 blocking bugs + 4 latent issues fixed |
| 3 | (Bonus) TLS on the NGINX ingress, port 443 | Done - verified with curl against a local CA |

This document has three parts: **how to reproduce** the solution (section 2), **what was wrong and why** (section 3-4), and the **chronological action log** with cause and result of every step taken (section 6).

---

## 1. Environment used

| Component | Version | Note |
|-----------|---------|------|
| Host OS | Windows 11 Pro (Git Bash for scripts) | |
| Docker Desktop | 29.4.0 (8 CPU / 16 GiB) | kind runs nodes as containers |
| kind | v0.32.0 -> node image kindest/node v1.36.1 | chosen over minikube: one container, fastest start, native hostPort mapping |
| kubectl | v1.34.1 | shipped with Docker Desktop |
| Helm | v4.3.0 | installed with `winget install Helm.Helm` |
| ingress-nginx | controller v1.12.1 (upstream "kind" manifest) | hostPort 80/443 on the control-plane node |
| Application image | `ealen/echo-server:0.5.2` (Node 16, Alpine) | as pinned by `Chart.appVersion` |

Why kind and not minikube: a single node container with ports 80/443 published directly on `127.0.0.1` means no VM, no tunnel, no `minikube ip`, and the README's `/etc/hosts` instruction works unchanged with `127.0.0.1`.

---

## 2. Reproduce the solution (step by step)

Prerequisites: Docker Desktop running, `kind`, `kubectl`, `helm`, `openssl`, `curl` on PATH (Git Bash on Windows, or any Linux/macOS shell).

```bash
git clone <this repo> && cd solution
git checkout feature/http-echo-fix-and-tls

scripts/01-create-cluster.sh      # kind cluster "thetaray", ports 80/443 -> localhost
scripts/02-install-ingress.sh     # ingress-nginx for kind, waits until the controller is Ready
scripts/03-create-tls-secret.sh   # local CA + server cert -> Secret http-echo/http-echo-tls
scripts/04-deploy.sh              # helm lint + helm upgrade --install --wait + helm test
scripts/05-verify.sh              # curl over HTTP and HTTPS through the ingress, shows the cert
```

Browser / plain-curl check (as described in the assignment README):

1. Add to the hosts file (`C:\Windows\System32\drivers\etc\hosts` as Administrator, or `/etc/hosts`):
   ```
   127.0.0.1 http-echo.k8s-server.local
   ```
2. Open `http://http-echo.k8s-server.local/` -> JSON echo of the request.
3. Open `https://http-echo.k8s-server.local/` -> same JSON, `x-forwarded-proto: https`.
   The certificate is issued by the local CA generated in step 03 (`tls/ca.crt`). Import that CA into the
   OS/browser trust store to get a green padlock, or use `curl --cacert tls/ca.crt`.
   On Windows curl (Schannel build) add `--ssl-no-revoke` because a private CA has no CRL endpoint.

Clean up: `kind delete cluster --name thetaray`.

Repository layout:

```
solution/
  http-echo/                 the Helm chart (fixed)
    Chart.yaml  values.yaml  .helmignore
    templates/{deployment,service,ingress,hpa,serviceaccount}.yaml, _helpers.tpl, NOTES.txt
    templates/tests/test-connection.yaml
  cluster/
    kind-config.yaml         kind cluster definition (ingress-ready label, hostPort 80/443)
    ingress-nginx-kind.yaml  upstream ingress-nginx manifest, vendored for reproducibility
  scripts/01..05-*.sh        idempotent, reproducible setup / deploy / verify
  tls/                       generated at runtime by script 03, git-ignored (private keys)
  SOLUTION.md                this file
```

---

## 3. Diagnosis - what was broken

Symptoms observed after installing the chart exactly as received (`helm install http-echo ./http-echo`):

```
NAME                         READY   STATUS    RESTARTS
http-echo-7589ff9455-qssp2   0/1     Running   0

Warning  Unhealthy  Liveness probe errored and resulted in unknown state ... exec: "/bin/bash": stat /bin/bash: no such file or directory
Warning  Unhealthy  Readiness probe failed: Get "http://10.244.0.8:5678/": dial tcp 10.244.0.8:5678: connect: connection refused

service/http-echo   ClusterIP   10.96.161.188   <none>   5678/UDP
curl http://http-echo.k8s-server.local/   ->   HTTP 503   (ingress has no ready endpoint)
```

Inside the pod: `netstat -tln` showed the process listening on `:::80`, not 5678.
`docker image inspect ealen/echo-server:0.5.2` showed `Entrypoint=["node","webserver"]`, no `/bin/bash`, Alpine base.

### 3.1 Blocking bugs (each one alone keeps the service down)

| # | File | Bug | Effect | Fix |
|---|------|-----|--------|-----|
| 1 | `templates/deployment.yaml` | `args: [-port, "5678"]` - flags belong to hashicorp/http-echo, not to `ealen/echo-server` whose entrypoint is `node webserver` and which reads the **`PORT` env var** (default 80) | App listens on 80, `containerPort`/probes/Service target 5678 -> readiness never passes, 0 endpoints, ingress 503 | Removed `args`, added `env: PORT=<app.port>`; `containerPort` now templated from the same value so they cannot diverge |
| 2 | `templates/deployment.yaml` | Liveness probe is `exec /bin/bash -c wget ...` | Image is Alpine: no bash. Probe errors on every run ("unknown state"). It also hard-coded the port and used an exec fork for what is a plain HTTP check | Replaced with an `httpGet` probe on the named port; probe spec moved to values so timings are tunable without editing templates |
| 3 | `templates/service.yaml` | `protocol: UDP` | Ingress-nginx forwards TCP to a UDP service port; nothing can connect | `protocol: TCP` |
| 4 | `values.yaml` | `resources.requests.cpu: "6"`, `memory: "1Mi"` | Requests 6 full cores for a ~0 CPU echo server. On this 8-CPU kind node it scheduled; on a default 2-CPU minikube node the pod stays **Pending / Insufficient cpu**. 1Mi memory is below the real ~18 MiB footprint | Measured with `docker stats` (17.8 MiB idle). Set `requests cpu 10m / memory 32Mi`, `limits memory 64Mi`, no CPU limit (avoids CFS throttling latency) |
| 5 | chart structure | Files delivered flat; `.helmignore` arrived as a file named `download`; templates not under `templates/` | `helm install` cannot consume it as a chart | Restored standard layout on `main` as the baseline commit (no content changes) |

### 3.2 Latent issues (not blocking today, would bite in production / on upgrade)

| # | File | Issue | Fix |
|---|------|-------|-----|
| 6 | `templates/hpa.yaml` | `autoscaling/v2beta1` was removed in Kubernetes 1.26. Enabling `autoscaling.enabled` on a current cluster fails with "no matches for kind HorizontalPodAutoscaler in version autoscaling/v2beta1" | Migrated to `autoscaling/v2` (`target.type: Utilization / averageUtilization`) |
| 7 | `values.yaml` | `autoscaling.maxReplicas: 100` for a lab echo service | 5 |
| 8 | `values.yaml` / deployment | No security context, runs as root, writable rootfs, SA token auto-mounted although the app never calls the API | `runAsNonRoot 1000`, `readOnlyRootFilesystem`, `drop ALL` capabilities, `allowPrivilegeEscalation: false`, `seccomp RuntimeDefault`, `automountServiceAccountToken: false`. Verified in-pod: `uid=1000(node)`, `touch /tmp/x -> Read-only file system`, app still serves |
| 9 | `templates/tests/test-connection.yaml` | `image: busybox` unpinned, no resources, runs as root, test pod never cleaned up | Pinned `busybox:1.36`, resources, non-root, `hook-delete-policy: hook-succeeded` |
| 10 | `Chart.yaml` | Version not bumped although templates changed; boilerplate description | `version: 0.2.0`, `kubeVersion: ">=1.19.0-0"`, real description |

Nothing was wrong with `ingress.yaml`, `serviceaccount.yaml`, `_helpers.tpl` or `NOTES.txt`; they are unchanged apart from being fed correct values.

---

## 4. TLS (Step 3) - design

* Termination at the ingress controller (ingress-nginx already listens on 443 via the kind hostPort mapping). The pod stays plain HTTP inside the cluster - standard pattern, zero change to the application.
* Certificate: `scripts/03-create-tls-secret.sh` creates a local CA (`tls/ca.crt`, 10 years) and a server certificate for `http-echo.k8s-server.local` with a proper **SAN** (modern clients ignore CN), `extendedKeyUsage=serverAuth`, 1 year. Stored as a `kubernetes.io/tls` Secret `http-echo-tls` in the app namespace.
* The chart only **references** the secret (`ingress.tls[0].secretName`). Keys never live in the chart or in git (`tls/` is git-ignored). In production the same values block works unchanged with cert-manager (`cert-manager.io/cluster-issuer` annotation) or a corporate CA-signed certificate.
* `nginx.ingress.kubernetes.io/ssl-redirect: "false"` is set on purpose so the assignment's HTTP check (Step 2) and HTTPS check (Step 3) both pass as written. In production flip it to `"true"` (one value) to force every client onto TLS.

Verification result (`scripts/05-verify.sh`):

```
== HTTPS (verified against the local CA) ==
{"host":{"hostname":"http-echo.k8s-server.local",...},"request":{"headers":{...,"x-forwarded-port":"443","x-forwarded-proto":"https","x-forwarded-scheme":"https","x-scheme":"https",...}},
 "environment":{...,"HOSTNAME":"http-echo-68b7cd6b96-8jjm5","PORT":"5678","HTTP_ECHO_SERVICE_PORT":"5678",...}}
status=200 ssl_verify_result=0
== HTTPS without the CA must be rejected (proves verification is real) ==
rejected as expected        (curl: SEC_E_UNTRUSTED_ROOT)
== certificate presented by the ingress ==
subject=CN=http-echo.k8s-server.local   issuer=CN=http-echo local CA
X509v3 Subject Alternative Name: DNS:http-echo.k8s-server.local
notBefore=Oct  9 15:01:59 2026 GMT  notAfter=Oct  9 15:01:59 2027 GMT
```

---

## 5. Final state

```
$ kubectl -n http-echo get pods,svc,ingress
pod/http-echo-68b7cd6b96-8jjm5   1/1   Running   0 restarts
service/http-echo   ClusterIP   10.96.161.188   5678/TCP
ingress.networking.k8s.io/http-echo   nginx   http-echo.k8s-server.local   localhost   80, 443

$ helm test http-echo -n http-echo      ->  Phase: Succeeded
$ kubectl -n http-echo get events --field-selector type=Warning,involvedObject.name=<pod>   ->  No resources found
$ curl http://http-echo.k8s-server.local/    ->  200, JSON echo  (x-forwarded-proto: http)
$ curl https://http-echo.k8s-server.local/   ->  200, JSON echo  (x-forwarded-proto: https)
```

---

## 6. Action log (chronological - action, cause, result)

| # | Action | Cause / why | Result |
|---|--------|-------------|--------|
| 1 | Read the assignment README and all 13 chart files | Understand the three steps and spot planted faults before touching a cluster | Suspected: UDP service, `-port` args, bash exec probe, 6-CPU request, v2beta1 HPA, flat chart layout |
| 2 | Inventory tooling (`docker`, `kind`, `kubectl`, `helm`, `git`, `openssl`) | Decide cluster tool without installing more than needed | Docker Desktop + kind + kubectl present; Helm and minikube missing; Docker daemon not running |
| 3 | Start Docker Desktop; `winget install Helm.Helm` | Both are hard prerequisites | Docker 29.4.0 up after ~5 s; Helm 4.3.0 installed (binary not on PATH in the current shell, called by full path until shell restart) |
| 4 | Create `solution/`, copy chart into standard Helm layout, rename `download` -> `.helmignore`, `git init -b main`, commit as **baseline** | Submission must be a git branch; a baseline commit lets the reviewer `git diff main..feature/...` and see exactly what changed | Commit `a4bea27` "Baseline: original http-echo chart as received (broken)" |
| 5 | Add `.gitattributes` (`eol=lf`), `core.autocrlf=false` | Windows checkout was about to rewrite every file to CRLF, which would pollute the diff and break `#!/usr/bin/env bash` scripts | Clean LF files, clean diffs |
| 6 | Write `cluster/kind-config.yaml`; `kind create cluster --wait 120s` | Need an ingress-reachable local cluster. kind config maps host 80/443 into the node and labels it `ingress-ready=true` as the upstream ingress-nginx manifest expects | Cluster `thetaray` Ready after 22 s, Kubernetes v1.36.1, context `kind-thetaray` |
| 7 | `docker pull ealen/echo-server:0.5.2` + `docker image inspect` + `sh` into it | Confirm, not assume, how the app is configured and what tools the image has | `Entrypoint=["node","webserver"]`, no `/bin/bash`, busybox `wget` present, Alpine, Node 16.15 - confirms bugs 1 and 2 |
| 8 | Download upstream ingress-nginx kind manifest into `cluster/`, apply, wait for controller | Step 1 requirement; vendoring the manifest pins the version (v1.12.1) for reproducibility | Controller Running, admission jobs Completed, IngressClass `nginx` created |
| 9 | `helm lint` + `helm template` on the original chart | Establish whether the chart is syntactically broken or semantically broken | Lint passes, renders fine -> the faults are semantic, they only show at runtime |
| 10 | `helm install` the **original** chart, wait 75 s, collect `get pods`, `describe`, events, `netstat` in pod, `curl` through ingress | Reproduce the failure with evidence instead of fixing blind | Pod 0/1, liveness exec error (`/bin/bash` missing), readiness refused on 5678, app actually listening on 80, Service `5678/UDP`, ingress returns 503 |
| 11 | Run the image locally with `--read-only --user 1000:1000 --cap-drop ALL -e PORT=5678`; `docker stats` | Check the hardening I intend to apply is compatible with the app, and size resources from a measurement | HTTP 200 under full hardening; 17.8 MiB RSS, 0.01 % CPU idle |
| 12 | Check hosts file and admin rights | README verification uses a hostname | No hosts entry, shell not elevated -> verification scripts use `curl --resolve`; hosts-file step documented for the reviewer |
| 13 | `git checkout -b feature/http-echo-fix-and-tls` | Required submission format | Branch created from baseline |
| 14 | Rewrite `values.yaml`, `Chart.yaml`, `deployment.yaml`, `service.yaml`, `hpa.yaml`, `tests/test-connection.yaml` (see section 3) | Fix the 5 blocking bugs and the 5 latent issues in one coherent change | See diff `git diff main..feature/http-echo-fix-and-tls -- http-echo/` |
| 15 | Write `scripts/01..05` + `.gitignore` (`tls/`) | Reviewer should be able to reproduce in five commands; private keys must never be committed | Idempotent scripts; `kind get clusters` guard, `--dry-run=client | apply` for the secret |
| 16 | `helm lint` + `helm template` on the fixed chart | Catch template errors before touching the cluster | Lint clean; render shows TCP, `PORT=5678`, httpGet probes, security context, tls block |
| 17 | `scripts/03-create-tls-secret.sh` | Step 3 needs a certificate before the ingress can serve 443 | Secret `http-echo/http-echo-tls` type `kubernetes.io/tls`; cert SAN = `http-echo.k8s-server.local`; first attempt hit the Git Bash path-mangling of `/CN=...`, solved with `MSYS_NO_PATHCONV=1` inside the script |
| 18 | `scripts/04-deploy.sh` (`helm upgrade --install --wait`, `helm test`) | Deploy fix over the broken release in place (revision 2) to also prove upgrade path works | Pod 1/1 in 7 s, old pod terminated, `helm test` Phase Succeeded, ingress shows ports `80, 443` |
| 19 | `scripts/05-verify.sh` | Prove Step 2 and Step 3 from outside the cluster | HTTP 200 OK. HTTPS failed with `curl (60) schannel: revocation status is unknown` |
| 20 | Diagnose HTTPS failure: run curl **without** `--cacert` | Determine whether the problem is server-side or client-side | `SEC_E_UNTRUSTED_ROOT` -> server cert and chain are fine and really verified; the error is the Windows Schannel curl insisting on a CRL that a private CA does not publish |
| 21 | Make `05-verify.sh` add `--ssl-no-revoke` only when curl reports Schannel; add a negative test (no CA -> must be rejected) | Keep the script portable (Linux/macOS curl unaffected) and make the verification self-checking | HTTPS 200, `ssl_verify_result=0`, negative test "rejected as expected" |
| 22 | Add `readinessProbe.initialDelaySeconds: 3` | One transient `connection refused` Warning event appeared at startup (probe fired before Node bound the socket); harmless but noisy in production alerting | Redeployed as revision 3; **zero** Warning events on the new pod |
| 23 | Verify stability after 45 s, in-pod identity, endpoints | Final acceptance | 0 restarts, `uid=1000(node)`, rootfs read-only, listening `:::5678`, EndpointSlice ready=true |
| 24 | Server-side dry-run of the HPA from the original chart vs the fixed chart (`--set autoscaling.enabled=true`) | Prove latent issue 6 instead of asserting it | Original: `no matches for kind "HorizontalPodAutoscaler" in version "autoscaling/v2beta1"`. Fixed: `created (server dry run)`. Node allocatable CPU confirmed as 8, explaining why the 6-CPU request scheduled here |
| 25 | Write this document, commit the branch | Submission requirement: branch + explanation of important issues | Commits on `feature/http-echo-fix-and-tls` |

---

## 7. Production notes (what I would add beyond the 2-4 h scope)

* **Certificates**: cert-manager with a ClusterIssuer (internal CA or ACME); the chart already consumes `ingress.tls[].secretName`, so only an annotation changes. Set `ssl-redirect: "true"` and add HSTS via the ingress-nginx ConfigMap.
* **Availability**: `replicaCount: 2`, `podAntiAffinity` across nodes, a `PodDisruptionBudget` (`minAvailable: 1`), `topologySpreadConstraints` on multi-zone clusters.
* **Autoscaling**: needs metrics-server; HPA is now `autoscaling/v2` so it just works once metrics exist.
* **Network policy**: default-deny in the namespace, allow ingress only from the `ingress-nginx` namespace to port 5678.
* **Supply chain**: pin the image by digest (`ealen/echo-server@sha256:...`), and ideally move to the current upstream release (0.9.x) after testing; run Trivy in CI.
* **CI**: `helm lint`, `helm template | kubeconform`, `ct lint/install` in a kind cluster on every PR; `helm-docs` for a generated values table.
* **Observability**: ingress-nginx metrics are already exposed; add a ServiceMonitor and an alert on `nginx_ingress_controller_requests{status=~"5.."}`.
* **Ingress hardening**: rate limiting annotations, `proxy-body-size`, and `server-snippet` restrictions; the echo server reflects every header and env var it sees, so in a real environment it must never be exposed outside a trusted network (it leaks `HOSTNAME`, service IPs, etc.).

---

## 8. Known limitations of this lab setup

* Ports 80/443 must be free on the host; otherwise change `hostPort` in `cluster/kind-config.yaml` and use `http://host:PORT/`.
* The hosts-file entry needs Administrator rights on Windows; the scripts therefore verify with `curl --resolve`, which is equivalent for the ingress (the `Host` header is what ingress-nginx routes on).
* The local CA is self-generated; browsers show a warning until `tls/ca.crt` is imported. This is expected for a local cluster and is exactly what cert-manager/ACME replaces in production.
