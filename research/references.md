# References for the technical deep-dive

Compiled 2026-10-10. Every URL below was fetched and read during compilation; quotes are verbatim from the page as served on that date (page versions noted where the site shows one). Where a fact comes from source code rather than prose docs, the file path is given. Anything that could not be verified is flagged explicitly rather than guessed.

---

## Topic 1 — ealen/echo-server and hashicorp/http-echo

- [Ealenn/Echo-Server (GitHub README)](https://github.com/Ealenn/Echo-Server) — GitHub README
  - "An echo server is a server that replicates the request sent by the client and sends it back."
  - Docker image is `ealen/echo-server`; README run example: `docker run -p 8080:80 ealen/echo-server`. Docs link: "Read the docs : https://ealenn.github.io/Echo-Server".
  - Configuration table (Environment | Helm | CLI | Default): `PORT` | `service.port` | `--port` | `80`; `LOGS__IGNORE__PING` | `application.logs.ignore.ping` | `--logs:ignore:ping` | `false`; `ENABLE__HOST`, `ENABLE__HTTP`, `ENABLE__REQUEST`, `ENABLE__COOKIES`, `ENABLE__HEADER`, `ENABLE__ENVIRONMENT`, `ENABLE__FILE` all default `true` (Helm keys `application.enable.<name>`, CLI `--enable:<name>`).
  - Latency controls `CONTROLS__TIMES__MIN` (0) / `CONTROLS__TIMES__MAX` (60000); request commands such as `COMMANDS__HTTPBODY__QUERY` (`echo_body`), `COMMANDS__HTTPCODE__QUERY` (`echo_code`), `COMMANDS__TIME__HEADER` (`x-echo-time`), `COMMANDS__FILE__QUERY` (`echo_file`); logging `LOGS__APP` (echo-server), `LOGS__LEVEL` (debug), `LOGS__FORMAT` (default | line | object).
  - NodeJS run instructions in README: `node ./src/webserver --port 8080` or `PORT=8080 npm run start`.
- [Echo-Server docs site](https://ealenn.github.io/Echo-Server/) — official docs (sub-pages: `/pages/configuration/`, `/pages/quick-start/docker.html`, `/pages/quick-start/kubernetes.html`, `/pages/quick-start/helm.html`)
  - Configuration index page lists `PORT` | CLI `--port` | default `80`.
  - Feature-toggle page: "This configuration is used to deactivate some elements in the response." (ENABLE__HOST / HTTP / REQUEST / COOKIES / ENVIRONMENT / FILE / HEADER, all default `true`).
  - Docker quick-start uses `docker run -d -p 3000:80 ealen/echo-server:0.9.2` and `curl -I localhost:3000` (response begins `HTTP/1.1 200 OK`).
  - Kubernetes quick-start: "Creates deployment with `5` replicas", "Creates Ingress with `kubernetes.io/ingress.class: nginx` annotation".
  - Note: neither the README nor the docs site shows a full example JSON response body; the field list below comes from source.
- [Echo-Server Dockerfile](https://raw.githubusercontent.com/Ealenn/Echo-Server/master/Dockerfile) — GitHub source (master, 2026-10-10)
  - Both build and final stage are `FROM node:lts-alpine` (build stage uses `--platform=$BUILDPLATFORM`).
  - `ENTRYPOINT ["node", "webserver"]`; no `CMD`, no `EXPOSE`, no `USER`, no `ENV` lines. Consequence: anything in Kubernetes `args:` is appended to `node webserver`, and the server parses it with nconf (see next source).
- [Echo-Server source: `src/nconf.js`, `src/global.json`, `src/app.js`, `src/response/*.js`, `src/middlewares/logMiddleware.js`](https://github.com/Ealenn/Echo-Server/tree/master/src) — GitHub source (master)
  - `nconf.js`: config chain is `.argv({ parseValues: true })` then `.env({ separator: '__', lowerCase: true, parseValues: true })` then `.file({ file: path.join(__dirname, 'global.json') })`. So CLI `--port`, env `PORT`, and the defaults file all feed the same key `port`; `__` in env names maps to nested keys (`ENABLE__HOST` -> `enable:host`).
  - `global.json` defaults: `"port": 80`; `enable.host/http/request/cookies/environment/file/header` all `true`; `logs.ignore.ping: false`.
  - `webserver.js`: `app.listen(config.get('port'), () => console.debug(\`Listening on port ${config.get('port')}.\`));`
  - `app.js`: single catch-all route `app.all('*', (req, res) => res.json({ host: require('./response/host')(req), http: require('./response/http')(req), request: require('./response/request')(req), environment: require('./response/environment')(req) }))`. There is no dedicated `/ping` or health route; `/ping` is served by the catch-all.
  - Response fields: `host` = `{ hostname: req.hostname, ip: req.ip, ips: req.ips }` (gated by `enable:host`); `http` = `{ method, baseUrl, originalUrl, protocol }` from `req` (gated by `enable:http`); `request` = `{ params, query, cookies, body, headers }` (gated by `enable:request`; `cookies` additionally by `enable:cookies`, which when off also deletes the `cookie` header); `environment` = `process.env` (gated by `enable:environment`).
  - `logMiddleware.js`: `if (req.originalUrl != "/ping" || !config.get('logs:ignore:ping')) { ... }` — a request is a "ping" only when `originalUrl` is exactly `/ping`, and it is omitted from logs only when `LOGS__IGNORE__PING=true`.
- [hashicorp/http-echo (GitHub README)](https://github.com/hashicorp/http-echo) — GitHub README
  - "HTTP Echo is a small go web server that serves the contents it was started with as an HTML page."
  - "The default port is 5678, but this is configurable via the `-listen` flag:" `http-echo -listen=:8080 -text="hello world"`.
- [hashicorp/http-echo `main.go`](https://raw.githubusercontent.com/hashicorp/http-echo/main/main.go) — GitHub source (main)
  - `listenFlag = flag.String("listen", ":5678", "address and port to listen")`
  - `textFlag = flag.String("text", "", "text to put on the webpage")`
  - `statusFlag = flag.Int("status-code", 200, "http response code, e.g.: 200")`
  - `echoText := os.Getenv("ECHO_TEXT")` (the `-text` flag overrides it). There is no `-port` flag and no `ECHO_LISTEN` env var; port is only settable via `-listen`.
  - The kind docs (Topic 8) use `hashicorp/http-echo:0.2.3` with `args: ["-text=foo"]` and `containerPort: 5678`, which is the likely origin of confusing http-echo's `-listen`/`-text` flags with echo-server's `--port`.

## Topic 2 — Kubernetes probes

- [Liveness, Readiness, and Startup Probes (concepts)](https://kubernetes.io/docs/concepts/configuration/liveness-readiness-startup-probes/) — official docs
  - "Liveness probes determine when to restart a container."
  - "Readiness probes determine when a container is ready to accept traffic."
  - "Startup probes verify whether the application within a container is started. If a startup probe is configured, Kubernetes does not execute liveness or readiness probes until the startup probe succeeds, allowing the application time to finish its initialization."
  - "If the readiness probe returns a failed state, the EndpointSlice controller removes the Pod's IP address from the EndpointSlices of all Services that match the Pod."
- [Configure Liveness, Readiness and Startup Probes (task)](https://kubernetes.io/docs/tasks/configure-pod-container/configure-liveness-readiness-startup-probes/) — official docs
  - exec: "To perform a probe, the kubelet executes the command `cat /tmp/healthy` in the target container. If the command succeeds, it returns 0, and the kubelet considers the container to be alive and healthy. If the command returns a non-zero value, the kubelet kills the container and restarts it."
  - httpGet: "Any code greater than or equal to 200 and less than 400 indicates success. Any other code indicates failure." "By default the `kubelet` sends HTTP/1.1 requests when executing an HTTP probe."
  - tcpSocket: "the kubelet will attempt to open a socket to your container on the specified port. If it can establish a connection, the container is considered healthy, if it can't it is considered a failure."
  - "Readiness probes run on the container during its whole lifecycle." "A pod with containers reporting that they are not ready does not receive traffic through Kubernetes Services." "The readiness and liveness probes do not depend on each other to succeed."
  - Startup probe sizing: "Thanks to the startup probe, the application will have a maximum of 5 minutes (30 * 10 = 300s) to finish its startup." (`failureThreshold: 30`, `periodSeconds: 10`).
  - gRPC: "There are no error codes for built-in probes. All errors are considered as probe failures." "gRPC probes do not support named ports."
- [Pod v1 API reference — Probe](https://kubernetes.io/docs/reference/kubernetes-api/workload-resources/pod-v1/) — official API reference (v1.37 docs build)
  - `periodSeconds`: "How often (in seconds) to perform the probe. Default to 10 seconds. Minimum value is 1."
  - `timeoutSeconds`: "Number of seconds after which the probe times out. Defaults to 1 second. Minimum value is 1."
  - `successThreshold`: "Minimum consecutive successes for the probe to be considered successful after having failed. Defaults to 1. Must be 1 for liveness and startup. Minimum value is 1."
  - `failureThreshold`: "Minimum consecutive failures for the probe to be considered failed after having succeeded. Defaults to 3. Minimum value is 1."
  - `initialDelaySeconds`: "Number of seconds after the container has started before liveness probes are initiated." (no default stated; effectively 0).
- [kubelet prober source `pkg/kubelet/prober/prober.go`](https://raw.githubusercontent.com/kubernetes/kubernetes/master/pkg/kubelet/prober/prober.go) — GitHub source (master)
  - The event text is built from `"%s probe errored and resulted in %s state: %s", probeType, result, err` and recorded as a `Warning` / `ContainerUnhealthy` event; the function then does `return results.Failure, err`. So "Liveness probe errored and resulted in unknown state" means the probe *could not run* (error path), the `%s` result was `probe.Unknown`, and the result is treated as a failure for threshold counting purposes.
  - A `probe.Unknown` result with no error is also mapped: `case probe.Unknown: ... return results.Failure, nil`.
  - `runProbeWithRetries` retries up to `maxProbeRetries` (3) and only returns the last error.
  - A missing handler yields `probe.Unknown` with `fmt.Errorf("missing probe handler for %s:%s", ...)`.
- [exec prober `pkg/probe/exec/exec.go`](https://raw.githubusercontent.com/kubernetes/kubernetes/master/pkg/probe/exec/exec.go) — GitHub source (master)
  - Non-zero exit (an `ExitError`): `return probe.Failure, string(data), nil`; exit 0: `probe.Success`.
  - Timeout (`remote.ErrCommandTimedOut`): `return probe.Failure, err.Error(), nil`.
  - Any other error (command could not be started, e.g. binary not found / runtime ExecSync failure): `return probe.Unknown, "", err` — this is the path that produces the "errored and resulted in unknown state" event.
- [kubernetes/kubernetes#116026 "Report event for the cases when probe returned Unknown result"](https://github.com/kubernetes/kubernetes/issues/116026) — GitHub issue (opened 2023-02-24 by Sergey Kanzhelev, closed 2025-01-09 via PR #125901)
  - Proposes surfacing Unknown probe results as log lines and warning events; a Nov-2024 comment notes Unknown results always come with an error, logged as "probe errored".

## Topic 3 — Service protocol, EndpointSlices, ingress-nginx upstreams

- [Protocols for Services](https://kubernetes.io/docs/reference/networking/service-protocols/) — official docs
  - "Kubernetes supports the following protocols with Services: SCTP, TCP (the default), UDP"; "There are 3 valid values for the `protocol` of a port for a Service."
  - "You can use TCP for any kind of Service, and it's the default network protocol."
  - "You can use UDP for most Services. For `type: LoadBalancer` Services, UDP support depends on the cloud provider offering this facility."
  - SCTP: "Stable since Kubernetes v1.20"; "SCTP is not supported on nodes that run Windows."
- [Service (concepts)](https://kubernetes.io/docs/concepts/services-networking/service/) — official docs
  - "The default protocol for Services is TCP; you can also use any other supported protocol."
  - "When using multiple ports for a Service, you must give all of your ports names so that these are unambiguous."
  - "A Service can map any incoming `port` to a `targetPort`. By default and for convenience, the `targetPort` is set to the same value as the `port` field."
  - EndpointSlices "Stable since Kubernetes v1.21"; Endpoints "Deprecated since Kubernetes v1.33"; "Because a Service can be linked with more than one EndpointSlice, the 1000 backing endpoint limit only affects the legacy Endpoints API."
- [EndpointSlices](https://kubernetes.io/docs/concepts/services-networking/endpoint-slices/) — official docs (Stable since v1.21)
  - "The control plane automatically creates EndpointSlices for any Kubernetes Service that has a selector specified."
  - "By default, the control plane creates and manages EndpointSlices to have no more than 100 endpoints each. You can configure this with the `--max-endpoints-per-slice` kube-controller-manager flag, up to a maximum of 1000."
  - Ownership "is indicated by an owner reference on each EndpointSlice as well as a `kubernetes.io/service-name` label".
  - "EndpointSlices act as the source of truth for kube-proxy when it comes to how to route internal traffic."
- [ingress-nginx: How it works](https://kubernetes.github.io/ingress-nginx/how-it-works/) — official docs
  - "On every endpoint change the controller fetches endpoints from all the services it sees"; it "sends these objects to a Lua handler running inside Nginx"; "The Lua code in turn stores those backends in a shared memory zone"; "Lua code running in `balancer_by_lua` context detects what endpoints it should choose upstream peer from".
  - "It is out of the scope of this Ingress controller to remove reloads completely." but endpoint-only changes do not require a reload.
- [ingress-nginx annotations: `service-upstream`](https://kubernetes.github.io/ingress-nginx/user-guide/nginx-configuration/annotations/) — official docs
  - "By default the Ingress-Nginx Controller uses a list of all endpoints (Pod IP/port) in the NGINX upstream configuration." With `nginx.ingress.kubernetes.io/service-upstream` it "instead uses a single upstream in NGINX, the service's Cluster IP and port." Known limitations: sticky sessions stop working and `proxy_next_upstream` has no effect.
  - `backend-protocol`: valid values HTTP, HTTPS, AUTO_HTTP, GRPC, GRPCS, FCGI; default HTTP.

## Topic 4 — Requests/limits, QoS, Pending, CPU-limit debate

- [Resource Management for Pods and Containers](https://kubernetes.io/docs/concepts/configuration/manage-resources-containers/) — official docs
  - "When you specify the resource request for containers in a Pod, the kube-scheduler uses this information to decide which node to place the Pod on. When you specify a resource limit for a container, the kubelet enforces those limits..."
  - "`cpu` limits are enforced by CPU throttling... Thus, a `cpu` limit is a hard limit the kernel enforces."
  - "`memory` limits are enforced by the kernel with out of memory (OOM) kills... This means `memory` limits are enforced reactively."
  - "If you specify a limit for a resource, but do not specify any request... then Kubernetes copies the limit you specified and uses it as the requested value for the resource."
  - Troubleshooting event example: `Warning  FailedScheduling  23s   default-scheduler  0/42 nodes available: insufficient cpu` — "the Pod named "frontend" fails to be scheduled due to insufficient CPU resource on any node." Remedies: add nodes, terminate unneeded Pods, "Check that the Pod is not larger than all the nodes", check taints.
  - "During each scheduling interval (time slice), the Linux kernel checks to see if this limit is exceeded; if so, the kernel waits before allowing that cgroup to resume execution." "container runtimes don't terminate Pods or containers for excessive CPU usage."
- [Pod Quality of Service Classes](https://kubernetes.io/docs/concepts/workloads/pods/pod-qos/) — official docs
  - Guaranteed: "Every Container in the Pod must have a memory limit and a memory request... the memory limit must equal the memory request... Every Container in the Pod must have a CPU limit and a CPU request... the CPU limit must equal the CPU request."
  - Burstable: "The Pod does not meet the criteria for QoS class `Guaranteed`. At least one Container in the Pod has a memory or CPU request or limit..."
  - BestEffort: "none of the Containers in the Pod have a memory limit or a memory request, and none of the Containers in the Pod have a CPU limit or a CPU request".
  - "When a Node runs out of resources, Kubernetes will first evict `BestEffort` Pods running on that Node, followed by `Burstable` and finally `Guaranteed` Pods."
- [Robusta: "For the love of God, stop using CPU limits on Kubernetes"](https://home.robusta.dev/blog/stop-using-cpu-limits) — blog (Natan Yellin, 2022-08-24, marked "Updated")
  - "In most cases, Kubernetes CPU limits do more harm than help." "In fact, they're the number one cause of Kubernetes CPU throttling."
  - "Pods always get the CPU requested by their CPU request!" Recommends accurate CPU requests for every pod, no CPU limits.
  - Memory: always set memory limits and requests, with each request equal to its limit (memory cannot be reclaimed without killing the process).
- [Datadog: "Kubernetes CPU limits and requests: A deep dive"](https://www.datadoghq.com/blog/kubernetes-cpu-requests-limits/) — blog (Ara Pulido, 2023-12-07)
  - CPU limit is enforced via a cgroup quota per period, period defaulting to 100 ms (100,000 µs); once the quota is used the container is throttled until the next period even if the node has idle CPU.
  - "CPU limits can throttle your application even when there are spare CPU cycles." "If requests are properly set as a reflection of CPU needs, this is less likely to happen."
  - Counter-view to Robusta: recommends limits == requests in staging to discover real needs; Guaranteed QoS requires limits == requests; monitor `container.cpu.throttled`.
- [kubernetes/kubernetes#67577 "CFS quotas can lead to unnecessary throttling"](https://github.com/kubernetes/kubernetes/issues/67577) — GitHub issue (opened 2018-08-20 by bobrik, closed 2020-11-01)
  - Root cause tracked to a Linux CFS bandwidth bug (kernel Bugzilla #198197); fixes 512ac999 (v4.18-rc4) and de53fd7, backported to 4.19.84 / 5.3.9; "those can lead to unnecessary throttling, especially for well behaved tenants."

## Topic 5 — HorizontalPodAutoscaler API versions

- [Deprecated API Migration Guide](https://kubernetes.io/docs/reference/using-api/deprecation-guide/) — official docs
  - v1.26: "The **autoscaling/v2beta2** API version of HorizontalPodAutoscaler is no longer served as of v1.26." "Migrate manifests and API clients to use the **autoscaling/v2** API version, available since v1.23." Notable change: "`targetAverageUtilization` is replaced with `target.averageUtilization` and `target.type: Utilization`."
  - v1.25: "The **autoscaling/v2beta1** API version of HorizontalPodAutoscaler is no longer served as of v1.25." Same migration guidance and same notable change.
- [Horizontal Pod Autoscaling](https://kubernetes.io/docs/tasks/run-application/horizontal-pod-autoscale/) — official docs
  - "The current stable version can be found in the `autoscaling/v2` API version which includes support for scaling on memory and custom metrics. The new fields introduced in `autoscaling/v2` are preserved as annotations when working with `autoscaling/v1`."
  - "The `metrics.k8s.io` API is usually provided by an add-on named Metrics Server, which needs to be launched separately."
  - Control loop "default interval is 15 seconds" (`--horizontal-pod-autoscaler-sync-period`).
  - "if some of the Pod's containers do not have the relevant resource request set, CPU utilization for the Pod will not be defined and the autoscaler will not take any action for that metric."
  - v2 metric syntax: `type: Resource / resource: { name: cpu, target: { type: Utilization, averageUtilization: 60 } }` — "Utilization is the ratio between the current usage of resource to the requested resources of the pod."
- [HorizontalPodAutoscaler Walkthrough](https://kubernetes.io/docs/tasks/run-application/horizontal-pod-autoscale-walkthrough/) — official docs
  - "To follow this walkthrough, you also need to use a cluster that has a Metrics Server deployed and configured."
  - `kubectl autoscale deployment php-apache --cpu=50% --min=1 --max=10` produces an `apiVersion: autoscaling/v2` object with `metrics: - type: Resource / resource: name: cpu / target: type: Utilization / averageUtilization: 50`.
- [kubernetes-sigs/metrics-server README](https://github.com/kubernetes-sigs/metrics-server) — GitHub README
  - "a scalable, efficient source of container resource metrics for Kubernetes built-in autoscaling pipelines"; "Metrics Server is meant only for autoscaling purposes."
  - Install: `kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml`.
  - "Kubelet certificate needs to be signed by cluster Certificate Authority"; `--kubelet-insecure-tls` is documented as a testing-only flag (commonly needed on kind/minikube).

## Topic 6 — Pod security context and Pod Security Standards

- [Configure a Security Context for a Pod or Container](https://kubernetes.io/docs/tasks/configure-pod-container/security-context/) — official docs
  - "Security settings that you specify for a Container apply only to the individual Container, and they override settings made at the Pod level when there is overlap."
  - `runAsUser` "specifies that for any Containers in the Pod, all processes run with user ID 1000"; `runAsGroup` "If this field is omitted, the primary group ID of the containers will be root(0)."
  - "`allowPrivilegeEscalation`: Controls whether a process can gain more privileges than its parent process, for example, by executing a setuid binary. This boolean value directly controls whether the `no_new_privs` flag gets set on the container process..." "If `allowPrivilegeEscalation` is not defined in the `securityContext` field of a container specification, then it will default to true."
  - "`readOnlyRootFilesystem`: Mounts the container's root filesystem as read-only."
  - Capabilities: "you must omit the `CAP_` portion of the constant. For example, to add `CAP_SYS_TIME`, include `SYS_TIME`".
  - seccomp: "Valid options for `type` include `RuntimeDefault`, `Unconfined`, and `Localhost`."
- [Pod v1 API reference — `runAsNonRoot`](https://kubernetes.io/docs/reference/kubernetes-api/workload-resources/pod-v1/) — official API reference
  - "Indicates that the container must run as a non-root user. If true, the Kubelet will validate the image at runtime to ensure that it does not run as UID 0 (root) and fail to start the container if it does. If unset or false, no such validation will be performed."
- [Pod Security Standards — Restricted profile](https://kubernetes.io/docs/concepts/security/pod-security-standards/) — official docs
  - Restricted = "Everything from the Baseline policy" plus:
  - Volume Types: only `configMap`, `csi`, `downwardAPI`, `emptyDir`, `ephemeral`, `persistentVolumeClaim`, `projected`, `secret`.
  - Privilege Escalation (v1.8+): `allowPrivilegeEscalation` allowed value `false`.
  - Running as Non-root: `runAsNonRoot` allowed value `true` ("The container fields may be undefined/nil if the pod-level `spec.securityContext.runAsNonRoot` is set to `true`.")
  - Running as Non-root user (v1.23+): `runAsUser` "any non-zero value" or undefined/null.
  - Seccomp (v1.19+): `seccompProfile.type` allowed `RuntimeDefault`, `Localhost`; "Both the `Unconfined` profile and the absence of a profile are prohibited."
  - Capabilities (v1.22+): "Containers must drop `ALL` capabilities, and are only permitted to add back the `NET_BIND_SERVICE` capability."
- [Configure Service Accounts for Pods](https://kubernetes.io/docs/tasks/configure-pod-container/configure-service-account/) — official docs
  - "You can opt out of automounting API credentials on `/var/run/secrets/kubernetes.io/serviceaccount/token` for a service account by setting `automountServiceAccountToken: false` on the ServiceAccount". "You can also opt out of automounting API credentials for a particular Pod".
  - "If both the ServiceAccount and the Pod's `.spec` specify a value for `automountServiceAccountToken`, the Pod spec takes precedence."

## Topic 7 — ingress-nginx TLS

- [Ingress (concepts) — TLS section](https://kubernetes.io/docs/concepts/services-networking/ingress/) — official docs
  - "The TLS secret must contain keys named `tls.crt` and `tls.key` that contain the certificate and private key to use for TLS." Example Secret has `type: kubernetes.io/tls`.
  - "The Ingress resource only supports a single TLS port, 443, and assumes TLS termination at the ingress point (traffic to the Service and its Pods is in plaintext)."
  - "If the TLS configuration section in an Ingress specifies different hosts, they are multiplexed on the same port according to the hostname specified through the SNI TLS extension (provided the Ingress controller supports SNI)."
  - "`hosts` in the `tls` section need to explicitly match the `host` in the `rules` section."
- [ingress-nginx User Guide: TLS/HTTPS](https://kubernetes.github.io/ingress-nginx/user-guide/tls/) — official docs
  - "Anytime we reference a TLS secret, we mean a PEM-encoded X.509, RSA (2048) secret." Create with `kubectl create secret tls ${CERT_NAME} --key ${KEY_FILE} --cert ${CERT_FILE}`.
  - Default cert: `--default-ssl-certificate` flag; "If this flag is not provided NGINX will use a self-signed certificate." "If the `tls:` section is not set, NGINX will provide the default certificate but will not force HTTPS redirect."
  - "By default the controller redirects HTTP clients to the HTTPS port 443 using a 308 Permanent Redirect response" when TLS is enabled; disable globally with ConfigMap `ssl-redirect: "false"` or per-Ingress with `nginx.ingress.kubernetes.io/ssl-redirect: "false"`; `force-ssl-redirect: "true"` enforces redirect "even when there is no TLS certificate available".
  - "HSTS is enabled by default." Disable with `hsts: "false"`.
  - SSL passthrough: "The `--enable-ssl-passthrough` flag enables the SSL Passthrough feature, which is disabled by default." "This bypasses NGINX completely and introduces a non-negligible performance penalty."
- [ingress-nginx ConfigMap reference](https://kubernetes.github.io/ingress-nginx/user-guide/nginx-configuration/configmap/) — official docs
  - `hsts` default `"true"` ("Enables or disables the header HSTS in servers running SSL."); `hsts-include-subdomains` default `"true"`; `hsts-max-age` default `"31536000"`; `hsts-preload` default `"false"`.
  - `ssl-redirect` default `"true"`; `force-ssl-redirect` default `"false"`; `ssl-protocols` default `TLSv1.2 TLSv1.3`.
- [ingress-nginx annotations: ssl-redirect / force-ssl-redirect](https://kubernetes.github.io/ingress-nginx/user-guide/nginx-configuration/annotations/) — official docs
  - "By default the controller redirects (308) to HTTPS if TLS is enabled for that ingress." `force-ssl-redirect` exists to "enforce a redirect to HTTPS even when there is no TLS certificate available" (e.g. SSL offloaded at an AWS ELB).
- [ingress-nginx source `internal/net/ssl/ssl.go`](https://raw.githubusercontent.com/kubernetes/ingress-nginx/main/internal/net/ssl/ssl.go) — GitHub source (main)
  - `GetFakeSSLCert()` calls `getFakeHostSSLCert("ingress.local")`; the generated cert has `Organization: []string{"Acme Co"}`, `CommonName: "Kubernetes Ingress Controller Fake Certificate"`, `DNSNames: []string{host}` (= `ingress.local`), valid 365 days ("This certificate is valid for 365 days"). This is the certificate curl/browsers show when no Ingress `tls` host/secret matches the requested SNI.

## Topic 8 — kind, extraPortMappings, ingress-ready, ingress-nginx on kind

- [kind docs: Ingress (v0.20.0 snapshot, `site/content/docs/user/ingress.md`)](https://raw.githubusercontent.com/kubernetes-sigs/kind/v0.20.0/site/content/docs/user/ingress.md) — official docs, historical version
  - Cluster config: `kubeadmConfigPatches: - | kind: InitConfiguration / nodeRegistration: / kubeletExtraArgs: / node-labels: "ingress-ready=true"` plus `extraPortMappings: - containerPort: 80 / hostPort: 80 / protocol: TCP - containerPort: 443 / hostPort: 443 / protocol: TCP`.
  - "extraPortMappings allow the local host to make requests to the Ingress controller over ports 80/443"; "node-labels only allow the ingress controller to run on a specific node(s) matching the label selector".
  - Ingress NGINX: `kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/main/deploy/static/provider/kind/deploy.yaml` then `kubectl wait --namespace ingress-nginx --for=condition=ready pod --selector=app.kubernetes.io/component=controller --timeout=90s`.
- [kind docs: Ingress (current page)](https://kind.sigs.k8s.io/docs/user/ingress/) — official docs (2026-10-10)
  - The page has been rewritten around cloud-provider-kind: cluster is created with plain `kind create cluster`; "For third-party ingress solutions (e.g., Ingress NGINX, Contour), please follow their official documentation." The `extraPortMappings` / `ingress-ready` recipe is no longer on this page (it is on the Configuration page and in the v0.20.0 snapshot above).
- [kind docs: Configuration — Extra Port Mappings](https://kind.sigs.k8s.io/docs/user/configuration/) — official docs
  - "Extra port mappings can be used to port forward to the kind nodes. This is a cross-platform option to get traffic into your kind cluster." With Docker Desktop on macOS/Windows/Linux you need port mappings (Linux without Docker Desktop can hit node IPs directly).
  - Example `extraPortMappings: - containerPort: 80 / hostPort: 80 / listenAddress: "127.0.0.1" / protocol: TCP`; "0.0.0.0 is the current default"; "TCP is the default".
  - "To use port mappings with NodePort, the kind node containerPort and the service nodePort needs to be equal."
  - The example Pod on this page is `image: hashicorp/http-echo:0.2.3`, `args: ["-text=foo"]`, `containerPort: 5678`.
- [ingress-nginx kind provider manifest (main → v1.15.1)](https://raw.githubusercontent.com/kubernetes/ingress-nginx/main/deploy/static/provider/kind/deploy.yaml) — GitHub source
  - Controller image `registry.k8s.io/ingress-nginx/controller:v1.15.1` (digest-pinned), namespace `ingress-nginx`, `hostPort: 80` and `hostPort: 443`, tolerations for `node-role.kubernetes.io/master` and `node-role.kubernetes.io/control-plane`.
  - Discrepancy to document: on `main` the Deployment's nodeSelector is only `kubernetes.io/os: linux` — the `ingress-ready: "true"` selector is gone.
- [ingress-nginx kind provider manifest (controller-v1.9.4 tag)](https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.9.4/deploy/static/provider/kind/deploy.yaml) — GitHub source
  - At v1.9.4 the nodeSelector was `ingress-ready: "true"` plus `kubernetes.io/os: linux`; Service `ingress-nginx-controller` is `type: NodePort`; image `registry.k8s.io/ingress-nginx/controller:v1.9.4`. This is why older tutorials insist on the `ingress-ready=true` node label.
- [ingress-nginx Installation Guide](https://kubernetes.github.io/ingress-nginx/deploy/) — official docs
  - minikube: "The ingress controller can be installed through minikube's addons system:" `minikube addons enable ingress`.
  - Generic readiness check: `kubectl wait --namespace ingress-nginx --for=condition=ready pod --selector=app.kubernetes.io/component=controller --timeout=120s`.
- [minikube Handbook: Accessing apps](https://minikube.sigs.k8s.io/docs/handbook/accessing/) — official docs
  - "The network is limited if using the Docker driver on Darwin, Windows, or WSL, and the Node IP is not reachable directly." NodePort via `minikube service <name> --url`; "Services of type `LoadBalancer` can be exposed via the `minikube tunnel` command." (On Windows/macOS Docker driver this is the reason kind's static `extraPortMappings` to `127.0.0.1:80/443` is a simpler local-ingress story than minikube's tunnel.)
- [kind Quick Start](https://kind.sigs.k8s.io/docs/user/quick-start/) — official docs
  - "kind runs a local Kubernetes cluster by using Docker containers as "nodes"." "Creating a Kubernetes cluster is as simple as `kind create cluster`." Docker Desktop: "you need a minimum of 6GB of RAM dedicated to the virtual machine (VM) running the Docker engine" (8GB recommended).

## Topic 9 — Helm

- [Helm docs: Charts](https://helm.sh/docs/topics/charts/) — official docs
  - Chart tree: `Chart.yaml` "A YAML file containing information about the chart"; `values.yaml` "The default configuration values for this chart"; `values.schema.json` "OPTIONAL: A JSON Schema for imposing a structure on the values.yaml file"; `charts/` "A directory containing any charts upon which this chart depends."; `crds/` "Custom Resource Definitions"; `templates/` "A directory of templates that, when combined with values," generate manifests; `templates/NOTES.txt` "OPTIONAL: A plain text file containing short usage notes" — "printed out after installation" and on `helm status`.
- [Helm docs: Named Templates](https://helm.sh/docs/chart_template_guide/named_templates/) — official docs
  - Files starting with an underscore are "assumed to not have a manifest inside" and "are not rendered to Kubernetes object definitions"; `_helpers.tpl` is "the default location for template partials".
  - "It is considered preferable to use `include` over `template`"; "A popular naming convention is to prefix each defined template with the name of the chart".
- [Helm docs: .helmignore](https://helm.sh/docs/chart_template_guide/helm_ignore_file/) — official docs
  - "The `.helmignore` file is used to specify files you don't want to include in your helm chart."
- [Helm docs: Chart Tests](https://helm.sh/docs/topics/chart_tests/) — official docs
  - A test "lives under the `templates/` directory and is a workload definition (commonly a Pod or Job)"; "The definition must contain the helm test hook annotation: `helm.sh/hook: test`."
  - "The container should exit successfully (exit 0) for a test to be considered a success." Run with `helm test <RELEASE_NAME>`. Placing tests in a `tests/` subdirectory is optional; `helm.sh/hook-weight` and `helm.sh/hook-delete-policy` "may be used with test resources".
- [Helm docs: Chart Hooks](https://helm.sh/docs/topics/charts_hooks/) — official docs
  - Hooks: `pre-install`, `post-install`, `pre-delete`, `post-delete`, `pre-upgrade`, `post-upgrade`, `pre-rollback`, `post-rollback`, `test` (`crd-install` removed in Helm 3).
  - `helm.sh/hook-delete-policy`: `before-hook-creation`, `hook-succeeded`, `hook-failed`; "If no hook deletion policy annotation is specified, the `before-hook-creation` behavior applies by default."
  - "Hook weights can be positive or negative numbers but must be represented as strings." "The resources that a hook creates are currently not tracked or managed as part of the release."
- [Helm docs: helm lint](https://helm.sh/docs/helm/helm_lint/) — official docs
  - "This command takes a path to a chart and runs a series of tests to verify that the chart is well-formed." Errors = would stop installation; warnings = convention violations; `--strict` = "fail on lint warnings".
- [Helm docs: helm template](https://helm.sh/docs/helm/helm_template/) — official docs
  - "Render chart templates locally and display the output." "Any values that would normally be looked up or retrieved in-cluster will be faked locally." "none of the server-side testing of chart validity (e.g. whether an API is supported) is done."
- [Helm docs: helm upgrade (Helm 4.3.0 page)](https://helm.sh/docs/helm/helm_upgrade/) — official docs
  - `--install`: "if a release by this name doesn't already exist, run an install"; `--wait`: "wait until resources are ready (up to --timeout). Use '--wait' alone for 'watcher' strategy"; `--timeout` "(default 5m0s)"; `--rollback-on-failure`: "if set, Helm will rollback the upgrade to previous success release upon failure." (`--atomic` is no longer listed on the Helm 4 page.)
- [Helm 3 docs: helm upgrade](https://helm.sh/docs/v3/helm/helm_upgrade) — official docs (v3)
  - `--atomic`: "if set, upgrade process rolls back changes made in case of failed upgrade." and `--wait` is turned on automatically when `--atomic` is used; `--wait`: "if set, will wait until all Pods, PVCs, Services..." are ready.
- [Helm docs: helm rollback / helm history](https://helm.sh/docs/helm/helm_rollback/) — official docs (see also https://helm.sh/docs/helm/helm_history/)
  - rollback takes a release name and "a revision (version) number"; omitting it (or 0) rolls back to the release immediately before the current one.
  - "History prints historical revisions for a given release." "A default maximum of 256 revisions will be returned."
- [Helm blog: Helm 4 Released](https://helm.sh/blog/helm-4-released) — official blog (post dated 2025-11-17)
  - "On Wednesday November 12th, during the Helm 4 presentation at KubeCon + CloudNativeCon, Helm v4.0.0 was released."
  - Highlights: "Redesigned plugin system that supports Web Assembly based plugins"; "Post-renderers are now plugins"; "Server side apply is now supported"; "Improved resource watching, to support waiting, based on kstatus"; "Logging via slog enabling SDK logging to integrate with modern loggers"; "Reproducible/Idempotent builds of chart archives".
  - Helm v3 support: "Bug fixes until July 8th 2026." "Security fixes until November 11th 2026." "NO features backported other than updates to the Kubernetes client libraries".
- [helm/helm release v4.0.0](https://github.com/helm/helm/releases/tag/v4.0.0) — GitHub release (12 Nov 2025)
  - Major release with "backward incompatible changes including to the flags and output of the Helm CLI."
- [Helm docs: Overview (Helm 4)](https://helm.sh/docs/overview) — official docs
  - "Some common CLI flags are renamed to better clarify their operation." `--atomic` → `--rollback-on-failure`, `--force` → `--force-replace`; old flags still work but emit a deprecation warning.
  - "Helm 4 will default to server-side apply when installing a new Chart release." "Helm 4 launches with three plugin types: CLI plugins, getter plugins, and post-renderer plugins." "Install charts by digest for better supply chain security."

## Topic 10 — TLS/PKI: SubjectAltName, openssl -addext, cert-manager

- [RFC 2818 §3.1 Server Identity](https://www.rfc-editor.org/rfc/rfc2818) — IETF RFC (May 2000)
  - "If a subjectAltName extension of type dNSName is present, that MUST be used as the identity."
  - "Although the use of the Common Name is existing practice, it is deprecated and Certification Authorities are encouraged to use the dNSName instead."
- [Eric Lawrence: "Chrome Deprecates Subject CN Matching"](https://textslashplain.com/2017/03/10/chrome-deprecates-subject-cn-matching/) — blog (2017-03-10)
  - From Chrome 58, "values in the Subject field will be ignored"; certificates must "specify the hostname(s) to which they apply in the SubjectAltName field."
  - "NET::ERR_CERT_COMMON_NAME_INVALID is an unfortunate error code, insofar as all common names are now ignored."
  - Corroborated via vendor/mailing-list copies of the Chromium policy `EnableCommonNameFallbackForLocalAnchors` (supported Chrome 58–65 only) found by search, e.g. [Epson KA-01066](https://www.epson.eu/en_EU/faq/KA-01066); the chromestatus.com entry could not be fetched.
- [OpenSSL `openssl-req` manual](https://docs.openssl.org/master/man1/openssl-req/) — official docs (master)
  - `-addext`: "Add a specific extension to the certificate (if -x509 is in use) or certificate request." "The argument must have the form of a `key=value` pair as it would appear in a configuration file."
  - Example in the man page: `openssl req -new -subj "/C=GB/CN=foo" -addext "subjectAltName = DNS:foo.co.uk" -addext "certificatePolicies = 1.2.3.4" -newkey rsa:2048 -keyout key.pem -out req.pem`.
  - Version note: the master man page does not state when `-addext` was introduced. Secondary evidence it arrived in OpenSSL 1.1.1 (11 Sep 2018): a 1.1.1-era `req(1)` man page lists `[-addext ext]` in its synopsis ([manpath.be c8 req](https://manpath.be/c8/1ssl/req)) and an [openssl-users post](https://mta.openssl.org/pipermail/openssl-users/2022-May/015198.html) shows it working on 1.1.1f: `openssl req -x509 -new -key ee.key -subj "/CN=test" -addext "subjectAltName = IP:1.2.3.4, DNS:test.com" -out ee.crt`. The official 1.1.1 man page on docs.openssl.org returned empty when fetched, so treat "1.1.1" as well-supported but not quoted from a primary OpenSSL document.
- [cert-manager: Securing Ingress Resources](https://cert-manager.io/docs/usage/ingress/) — official docs
  - "A small sub-component of cert-manager, ingress-shim, is responsible for this." (watching Ingresses and creating Certificate resources).
  - `cert-manager.io/cluster-issuer`: "the name of a cert-manager.io ClusterIssuer to acquire the certificate required for this Ingress."; `cert-manager.io/issuer`: "the name of the Issuer that should issue the certificate required for this Ingress." (namespaced Issuer must be in the Ingress's namespace).
  - The Ingress `tls[].secretName` is where the certificate lands: "cert-manager will store the created certificate in this secret."
  - Other supported annotations: `cert-manager.io/issuer-kind`, `issuer-group`, `kubernetes.io/tls-acme`, `acme.cert-manager.io/http01-ingress-class`, `cert-manager.io/common-name`, `duration`, `renew-before`, `usages`, `private-key-algorithm`, etc.
- [cert-manager: Issuer concept](https://cert-manager.io/docs/concepts/issuer/) — official docs
  - "it is not possible to issue certificates from an `Issuer` in a different namespace."; ClusterIssuer is "non-namespaced so it can be used to issue `Certificates` across all namespaces." In-tree types shown: SelfSigned, CA, Vault, CyberArk, ACME (HTTP01 / DNS01).

## Topic 11 — curl on Windows Schannel revocation errors

- [curl `lib/vtls/schannel_verify.c`](https://raw.githubusercontent.com/curl/curl/master/lib/vtls/schannel_verify.c) — GitHub source (master)
  - `else if(dwTrustErrorMask & CERT_TRUST_REVOCATION_STATUS_UNKNOWN) failf(data, "schannel: the revocation status is unknown");` → returns `CURLE_PEER_FAILED_VERIFICATION`.
  - `CERT_TRUST_IS_REVOKED` → "schannel: trust for this certificate or one of the certificates in the certificate chain has been revoked" → `CURLE_PEER_FAILED_VERIFICATION`.
  - `CertGetCertificateChain()` is called with `CERT_CHAIN_REVOCATION_CHECK_CHAIN` unless `conn_config->no_revoke` is set; `CERT_TRUST_IS_OFFLINE_REVOCATION` is cleared from the error mask only when `conn_config->revoke_best_effort` is set.
- [curl `lib/vtls/schannel.c`](https://raw.githubusercontent.com/curl/curl/master/lib/vtls/schannel.c) — GitHub source (master)
  - Default credential flags: `SCH_CRED_REVOCATION_CHECK_CHAIN` ("schannel: checking server certificate revocation").
  - `no_revoke`: `SCH_CRED_IGNORE_NO_REVOCATION_CHECK | SCH_CRED_IGNORE_REVOCATION_OFFLINE` ("schannel: disabled server certificate revocation checks").
  - `revoke_best_effort`: `SCH_CRED_IGNORE_NO_REVOCATION_CHECK | SCH_CRED_IGNORE_REVOCATION_OFFLINE | SCH_CRED_REVOCATION_CHECK_CHAIN` ("schannel: ignore revocation offline errors").
  - Handshake failures surface as "schannel: next InitializeSecurityContext failed: %s" (the commonly reported `0x80092012` / `0x80092013` variants come from this path).
- [curl docs: `--ssl-no-revoke`](https://raw.githubusercontent.com/curl/curl/master/docs/cmdline-opts/ssl-no-revoke.md) — official docs (cmdline-opts source)
  - Added in 7.44.0; Schannel-only; disables certificate revocation checks; "this option loosens the SSL security".
- [curl docs: `--ssl-revoke-best-effort`](https://raw.githubusercontent.com/curl/curl/master/docs/cmdline-opts/ssl-revoke-best-effort.md) — official docs (cmdline-opts source)
  - Added in 7.70.0; Schannel-only; "Ignore certificate revocation checks when they failed due to missing/offline distribution points" — keeps normal verification, only tolerates unreachable CRL/OCSP endpoints (the safer choice behind corporate proxies).
- [libcurl error codes](https://curl.se/libcurl/c/libcurl-errors.html) — official docs
  - `CURLE_PEER_FAILED_VERIFICATION (60)`: "The remote server's SSL certificate or SSH fingerprint was deemed not OK." "This error code has been unified with CURLE_SSL_CACERT since 7.62.0. Its previous value was 51." (This is the exit code 60 seen on the command line.)

## Topic 12 — Docker ENTRYPOINT/CMD vs Kubernetes command/args; Alpine; BusyBox wget

- [Dockerfile reference — CMD and ENTRYPOINT interaction](https://docs.docker.com/reference/dockerfile/) — official docs
  - "Dockerfile should specify at least one of `CMD` or `ENTRYPOINT` commands."; "`ENTRYPOINT` should be defined when using the container as an executable."; "`CMD` should be used as a way of defining default arguments for an `ENTRYPOINT` command"; "`CMD` will be overridden when running the container with alternative arguments."
  - Exec-form ENTRYPOINT + exec-form CMD: CMD items are appended to the ENTRYPOINT as arguments; shell-form ENTRYPOINT ignores CMD and runs under `/bin/sh -c`.
  - "If `CMD` is defined from the base image, setting `ENTRYPOINT` will reset `CMD` to an empty value."
  - Shell-form ENTRYPOINT: "the executable will not be the container's `PID 1`, and will not receive Unix signals." "Using the exec form doesn't automatically invoke a command shell."
- [Define a Command and Arguments for a Container](https://kubernetes.io/docs/tasks/inject-data-application/define-command-argument-container/) — official docs
  - "The command and arguments that you define in the configuration file override the default command and arguments provided by the container image. If you define args, but do not define a command, the default command is used with your new arguments."
  - "The `command` field corresponds to `ENTRYPOINT`, and the `args` field corresponds to `CMD` in some container runtimes."
  - "The command and arguments that you define cannot be changed after the Pod is created."
  - Env expansion requires `"$(VAR)"` syntax in `command`/`args`.
- [Pod v1 API reference — Container `command` / `args`](https://kubernetes.io/docs/reference/kubernetes-api/workload-resources/pod-v1/) — official API reference
  - `command`: "Entrypoint array. Not executed within a shell. The container image's ENTRYPOINT is used if this is not provided."
  - `args`: "Arguments to the entrypoint. The container image's CMD is used if this is not provided."
  - Applied to echo-server (`ENTRYPOINT ["node","webserver"]`, no CMD): `args: ["--port", "8080"]` becomes `node webserver --port 8080`, which nconf's `argv` parser accepts; `args: ["-port", "8080"]` (http-echo style) or a `-listen` flag is not an echo-server option.
- [Docker Hub: alpine](https://hub.docker.com/_/alpine) — official image description
  - "Alpine Linux is a Linux distribution built around musl libc and BusyBox." "The image is only 5 MB in size and has access to a package repository that is much more complete than other BusyBox based images."
- [Adrià Mercader: "TIL: Alpine Linux does not ship bash"](https://amercader.net/blog/til-alpine-linux-does-not-ship-bash) — blog (2022-11-28)
  - "Alpine linux doesn't include bash by default." A `#!/bin/bash` script fails with "exec /srv/app/start_ckan.sh: no such file or directory" because the interpreter, not the script, is missing. (Fix widely documented as `apk add --no-cache bash` or switching the shebang to `#!/bin/sh`.)
- [BusyBox command help (`BusyBox.html`)](https://busybox.net/downloads/BusyBox.html) — official docs
  - "BusyBox combines tiny versions of many common UNIX utilities into a single small executable."
  - `wget [-c|--continue] [-s|--spider] [-q|--quiet] [-O|--output-document file] [--header 'header: value'] [-Y|--proxy on/off] [-P DIR] [-U|--user-agent agent] url`; `-s` "Spider mode - only check file existence"; `-q` "Quiet"; `-O` "Save to filename ('-' for stdout)". Note: `-S`, `-T` and `--no-check-certificate` are not in this generic help listing (availability depends on the build's config), so prefer `wget -q -O- http://127.0.0.1:PORT/ping` style probes.

## Topic 13 — Production hardening one-liners

- [Disruptions (PDB concept)](https://kubernetes.io/docs/concepts/workloads/pods/disruptions/) — official docs
  - "A PDB limits the number of Pods of a replicated application that are down simultaneously from voluntary disruptions." "Involuntary disruptions cannot be prevented by PDBs; however they do count against the budget." "deleting deployments or pods bypasses Pod Disruption Budgets."
  - `kubectl drain` "tries to evict all of the Pods on the Node... The eviction request that `kubectl` submits on your behalf may be temporarily rejected, so the tool periodically retries".
- [Specifying a Disruption Budget](https://kubernetes.io/docs/tasks/run-application/configure-pdb/) — official docs (policy/v1)
  - `.spec.minAvailable` "the number of pods from that set that must still be available after the eviction"; `.spec.maxUnavailable` "the number of pods from that set that can be unavailable after the eviction"; "You can specify only one of `maxUnavailable` and `minAvailable` in a single `PodDisruptionBudget`."
- [Assigning Pods to Nodes — inter-pod anti-affinity](https://kubernetes.io/docs/concepts/scheduling-eviction/assign-pod-node/) — official docs
  - `requiredDuringSchedulingIgnoredDuringExecution` vs `preferredDuringSchedulingIgnoredDuringExecution`; "You express the topology domain (X) using a `topologyKey`".
  - "Inter-pod affinity and anti-affinity require substantial amounts of processing which can slow down scheduling in large clusters significantly. We do not recommend using them in clusters larger than several hundred nodes."
  - Redis example: "The `podAntiAffinity` rule tells the scheduler to avoid placing multiple replicas with the `app=store` label on a single node."
- [Pod Topology Spread Constraints](https://kubernetes.io/docs/concepts/scheduling-eviction/topology-spread-constraints/) — official docs
  - "control how Pods are spread across your cluster among failure-domains such as regions, zones, nodes"; fields `maxSkew` ("must be greater than zero"), `topologyKey`, `whenUnsatisfiable` (`DoNotSchedule` default / `ScheduleAnyway`), `labelSelector`.
  - vs anti-affinity: "`podAntiAffinity` repels Pods. If you set this to `requiredDuringSchedulingIgnoredDuringExecution` mode then only a single Pod can be scheduled into a single topology domain"; "For finer control, you can specify topology spread constraints".
- [Network Policies — default deny](https://kubernetes.io/docs/concepts/services-networking/network-policies/) — official docs
  - "Network policies are implemented by the network plugin... Creating a NetworkPolicy resource without a controller that implements it will have no effect." "Network policies do not conflict; they are additive."
  - Default deny ingress: `podSelector: {}` + `policyTypes: [Ingress]` — "This ensures that even pods that aren't selected by any other NetworkPolicy will still be isolated for ingress." Default deny all: `policyTypes: [Ingress, Egress]`.
- [Images — digests and pull policy](https://kubernetes.io/docs/concepts/containers/images/) — official docs
  - "Digests are hashes of the image's content, and are immutable. Tags can be moved to point to different images, but digests are fixed." `registry.k8s.io/pause:3.5@sha256:...` — "Only the digest will be used for pulling."
  - "You should avoid using the `:latest` tag when deploying containers in production as it is harder to track which version of the image is running and more difficult to roll back properly." "Specifying an image by digest pins the code that you run so that a change at the registry cannot lead to that mix of versions."
  - Workload default pull policy is `IfNotPresent` when unspecified.

---

## Quick facts table

| # | Topic | Fact | Source URL |
|---|-------|------|------------|
| 1 | echo-server | Default `PORT` is 80; CLI `--port`; env keys use `__` separator via nconf | https://github.com/Ealenn/Echo-Server |
| 2 | echo-server | Dockerfile: `FROM node:lts-alpine`, `ENTRYPOINT ["node","webserver"]`, no CMD/EXPOSE/USER | https://raw.githubusercontent.com/Ealenn/Echo-Server/master/Dockerfile |
| 3 | echo-server | Response JSON keys: `host`, `http`, `request`, `environment`; `/ping` has no special route, only log suppression via `LOGS__IGNORE__PING` | https://github.com/Ealenn/Echo-Server/tree/master/src |
| 4 | http-echo | Flags are `-listen` (default `:5678`), `-text`, `-status-code`; there is no `-port` flag | https://raw.githubusercontent.com/hashicorp/http-echo/main/main.go |
| 5 | Probes | Readiness failure: "the EndpointSlice controller removes the Pod's IP address from the EndpointSlices of all Services that match the Pod" | https://kubernetes.io/docs/concepts/configuration/liveness-readiness-startup-probes/ |
| 6 | Probes | Defaults: periodSeconds 10, timeoutSeconds 1, successThreshold 1, failureThreshold 3 | https://kubernetes.io/docs/reference/kubernetes-api/workload-resources/pod-v1/ |
| 7 | Probes | "probe errored and resulted in %s state" = exec could not run; result `probe.Unknown` is returned as `results.Failure` | https://raw.githubusercontent.com/kubernetes/kubernetes/master/pkg/kubelet/prober/prober.go |
| 8 | Probes | exec prober returns `probe.Unknown` + err when the command cannot start; non-zero exit = `probe.Failure` | https://raw.githubusercontent.com/kubernetes/kubernetes/master/pkg/probe/exec/exec.go |
| 9 | Service | Valid `protocol` values: TCP (default), UDP, SCTP | https://kubernetes.io/docs/reference/networking/service-protocols/ |
| 10 | EndpointSlices | Default max 100 endpoints per slice; Stable v1.21; Endpoints deprecated v1.33 | https://kubernetes.io/docs/concepts/services-networking/endpoint-slices/ |
| 11 | ingress-nginx | Upstreams are Pod endpoints by default; `service-upstream` annotation switches to the ClusterIP | https://kubernetes.github.io/ingress-nginx/user-guide/nginx-configuration/annotations/ |
| 12 | Resources | `FailedScheduling ... 0/42 nodes available: insufficient cpu` is the Pending signature for unsatisfiable CPU requests | https://kubernetes.io/docs/concepts/configuration/manage-resources-containers/ |
| 13 | QoS | Guaranteed requires CPU and memory limits == requests for every container | https://kubernetes.io/docs/concepts/workloads/pods/pod-qos/ |
| 14 | CPU limits | Robusta: "Kubernetes CPU limits do more harm than help"; set memory limit == request | https://home.robusta.dev/blog/stop-using-cpu-limits |
| 15 | HPA | `autoscaling/v2beta1` not served as of v1.25; `autoscaling/v2beta2` not served as of v1.26; `autoscaling/v2` available since v1.23 | https://kubernetes.io/docs/reference/using-api/deprecation-guide/ |
| 16 | HPA | `targetAverageUtilization` replaced by `target.type: Utilization` + `target.averageUtilization`; needs Metrics Server | https://kubernetes.io/docs/tasks/run-application/horizontal-pod-autoscale/ |
| 17 | Security | Restricted PSS: `allowPrivilegeEscalation: false`, `runAsNonRoot: true`, drop `ALL` (+ only `NET_BIND_SERVICE`), seccomp `RuntimeDefault`/`Localhost` | https://kubernetes.io/docs/concepts/security/pod-security-standards/ |
| 18 | Security | `automountServiceAccountToken` on the Pod spec takes precedence over the ServiceAccount | https://kubernetes.io/docs/tasks/configure-pod-container/configure-service-account/ |
| 19 | TLS | Ingress TLS secret must have `tls.crt` and `tls.key`; hosts multiplexed by SNI; termination at the ingress | https://kubernetes.io/docs/concepts/services-networking/ingress/ |
| 20 | TLS | ingress-nginx fake cert CN "Kubernetes Ingress Controller Fake Certificate", DNS `ingress.local`, 365 days | https://raw.githubusercontent.com/kubernetes/ingress-nginx/main/internal/net/ssl/ssl.go |
| 21 | TLS | HSTS on by default, `hsts-max-age` 31536000; `ssl-redirect` default true (308) | https://kubernetes.github.io/ingress-nginx/user-guide/nginx-configuration/configmap/ |
| 22 | kind | `extraPortMappings` 80/443 + `node-labels: "ingress-ready=true"`; apply `.../deploy/static/provider/kind/deploy.yaml` | https://raw.githubusercontent.com/kubernetes-sigs/kind/v0.20.0/site/content/docs/user/ingress.md |
| 23 | Helm | `helm.sh/hook-delete-policy` default is `before-hook-creation`; test hooks use `helm.sh/hook: test` and must exit 0 | https://helm.sh/docs/topics/charts_hooks/ |
| 24 | Helm 4 | Released 2025-11-12; `--atomic` → `--rollback-on-failure`, `--force` → `--force-replace`; server-side apply default on new installs; v3 bug fixes until 2026-07-08 | https://helm.sh/blog/helm-4-released |
| 25 | curl | "schannel: the revocation status is unknown" → `CURLE_PEER_FAILED_VERIFICATION` (60); `--ssl-no-revoke` (7.44.0) vs `--ssl-revoke-best-effort` (7.70.0) | https://raw.githubusercontent.com/curl/curl/master/lib/vtls/schannel_verify.c |
