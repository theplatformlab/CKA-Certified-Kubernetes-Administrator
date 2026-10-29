# Exercise 30 — TLS Configuration Update (Cipher Support)

> Supplemental application practice: changing TLS settings in an example service. This is not a named task in the current CKA curriculum; do not confuse it with Kubernetes control-plane certificate management.

Update TLS configuration to support additional protocol versions for backward compatibility. Tests ConfigMap modification and service restart.

## Conventions

TLS configuration troubleshooting involves configuration and restart traps:

- **Primary Trap:** ConfigMap edited but pod not restarted (config changes don't auto-reload)
- **Secondary Trap (Gotcha):** Conflating min-version with supported-versions (replacing vs adding support)
- **Validation Criteria:** Your fix is correct if:
  - `k edit cm` shows both TLS 1.2 and 1.3 in configuration
  - Pod is running after restart (check timestamps with `k get pod -owide`)
  - `openssl s_client -connect <ip>:<port> -tls1_2` shows "Protocol: TLSv1.2"
  - `openssl s_client -connect <ip>:<port> -tls1_3` shows "Protocol: TLSv1.3"
  - Both protocols work (don't break existing functionality)
- **Scoring:** Full credit for both TLS versions working + ConfigMap correct. Partial for config edit without restart.

## Tasks

Run `./scripts/lab.sh setup 30` first. Work in namespace `exercise-30`: setup deploys the Deployment `secure-web` (`nginx:1.28`, 1 replica) behind the ClusterIP Service `secure-web` on port 443. nginx terminates TLS with a self-signed certificate (Secret `secure-web-tls`) and reads its server config from the ConfigMap `secure-web-config`. The service currently supports only TLS 1.3.

1. Find where the TLS protocol setting comes from (`k describe deployment secure-web`, then the ConfigMap)
2. Add support for TLS 1.2 (make both available):
   - Add TLS 1.2 to the supported protocols in ConfigMap `secure-web-config`
   - Keep TLS 1.3 enabled; do not enable anything older than TLS 1.2
3. Restart the Deployment so nginx loads the new configuration
4. Verify the service accepts TLS 1.2 connections, from a pod in the cluster:
   - Use `openssl s_client -connect secure-web.exercise-30.svc.cluster.local:443 -tls1_2`
   - Or curl with explicit TLS 1.2
5. Verify TLS 1.3 still works

Validate with `./scripts/lab.sh check 30` — it handshakes with the Service using TLS 1.2 and TLS 1.3 from a throwaway pod.

## Key Learning

- TLS configuration often in ConfigMaps
- Adding vs replacing: exam specifies "ADD support" (don't remove existing)
- Service restart may be needed after config change
- TLS negotiation must support minimum version
- Testing TLS versions requires understanding openssl commands

## Hints

<details>
<summary>Stuck? Click to reveal hints</summary>

- Edit ConfigMap: `k edit cm <name>`
- Find TLS setting (could be `tlsVersion`, `tls1.3Min`, etc.)
- After edit, restart pod: `k rollout restart deployment/<name>`
- Test TLS 1.2: `openssl s_client -connect <ip>:<port> -tls1_2`
- Verify version in output: "Protocol  : TLSv1.2"
- Test TLS 1.3: `openssl s_client -connect <ip>:<port> -tls1_3`

</details>

## What tripped me up

> **Replace vs Add Trap (Reading Comprehension):** ConfigMap has `tls_min_version=1.3`. Exam says "ADD support for TLS 1.2." My instinct: replace it with `1.2` — this breaks 1.3. Correct approach: Change `tls_min_version=1.2` (allows 1.2 through 1.3+) or add a list `supported_versions=[1.2,1.3]`. Always read "ADD support" vs "REPLACE" vs "UPDATE" carefully. Adding ≠ Replacing.
>
> **ConfigMap Changes Don't Auto-Reload (Most Critical Gotcha):** Edited ConfigMap and tested immediately — still saw TLS 1.3 only. ConfigMaps mounted in pods are snapshot at pod start time. Changes to ConfigMap don't propagate to existing pods automatically. Must restart: `k rollout restart deployment/<name>`. Forget this step and your fix appears broken.
>
> **Finding the TLS Config (Location Varies):** TLS settings might be in:
  - ConfigMap env var: `TLS_MIN_VERSION=1.3`
  - ConfigMap file: `/etc/config/tls.conf` with `minVersion: 1.3`
  - Deployment spec: `--tls-min-version=1.3` flag
  - Secret: if using cert files
  Always first: `k describe deployment <name>` to see where config comes from. Then `k get cm <name> -o yaml` or `k edit cm <name>` to modify it.
>
> **May 2026 Gotcha (TLS 1.3 Restrictions):** In k8s 1.35, some components enforce TLS 1.3 minimum by default (e.g., api-server defaults to `1.3` or `1.2-1.3`). Downgrading to support `1.0` or `1.1` might be blocked by admission webhooks or security policies. Always check what the minimum supported version actually is in k8s 1.35 — it's usually not below 1.2.
>
> **openssl s_client Syntax for Testing:** Command is: `echo | openssl s_client -connect <ip>:<port> -tls1_2 2>/dev/null | grep Protocol`
  - Missing `-connect` format: wrong syntax
  - Missing version flag (e.g., just `-tls` instead of `-tls1_2`): tries multiple versions, hard to know which one succeeded
  - Forgetting `2>/dev/null`: diagnostic output clutters result
  - Missing `echo |`: command hangs waiting for input
  Test both after restart to confirm both versions work.
>
> **Restart Timing Issues:** After `k rollout restart`, pods take 10-30 seconds to start (depends on image size, node load). Testing immediately might hit a pod that's still starting or old pod that's terminating. Wait for stable: `k get pod -w` until all pods are `Running` and check again.
>
> **Service Endpoint Changes After Restart:** When you restart a deployment, the service endpoints temporarily become empty (no ready pods). During this window, `curl` calls to the service fail. Clients see connection refused. This is normal — wait for new pods to be ready. This can appear like your fix broke things when it's just timing.

## Verify

```bash
./scripts/lab.sh check 30
```

Manual checks:

```bash
# ConfigMap has both TLS 1.2 and 1.3
k -n exercise-30 get cm secure-web-config -o yaml | grep -i ssl_protocols

# Deployment is running after restart (pod AGE is recent)
k -n exercise-30 get deployment,pods

# Service endpoint is responding
k -n exercise-30 get svc secure-web -o wide

# Test both protocols from a pod (nginx:1.28 ships the openssl CLI)
k -n exercise-30 run tls-test --image=nginx:1.28 --rm -it --restart=Never -- bash
#   echo | openssl s_client -connect secure-web:443 -tls1_2 2>/dev/null | grep '^New'
#   Output: New, TLSv1.2, Cipher is ECDHE-RSA-AES256-GCM-SHA384
#   echo | openssl s_client -connect secure-web:443 -tls1_3 2>/dev/null | grep '^New'
#   Output: New, TLSv1.3, Cipher is TLS_AES_256_GCM_SHA384
#   curl -sk --tlsv1.2 --tls-max 1.2 https://secure-web     # secure-web OK
```

A failed handshake prints `New, (NONE), Cipher is (NONE)`. The `Protocol : TLSv1.2` line in the session block is printed even when the handshake failed — don't rely on it alone.

## Cleanup

```bash
./scripts/lab.sh cleanup 30
```

<details>
<summary>Solution</summary>

```bash
# 1. Find where the config comes from
k -n exercise-30 describe deployment secure-web   # Mounts: /etc/nginx/conf.d from secure-web-config

# 2. Check current TLS config
k -n exercise-30 get cm secure-web-config -o yaml
# ssl_protocols       TLSv1.3;

# 3. Edit ConfigMap to ADD TLS 1.2 (keep 1.3)
k -n exercise-30 edit cm secure-web-config
# Change to: ssl_protocols       TLSv1.2 TLSv1.3;

# 4. ConfigMap changes are not picked up by the running nginx: restart
k -n exercise-30 rollout restart deployment/secure-web

# 5. Wait for the new pod to be ready
k -n exercise-30 rollout status deployment/secure-web

# 6. Test TLS 1.2 and TLS 1.3 from inside the cluster
k -n exercise-30 run tls-test --image=nginx:1.28 --rm -it --restart=Never -- \
  sh -c 'for v in -tls1_2 -tls1_3; do echo | openssl s_client -connect secure-web:443 $v 2>/dev/null | grep "^New"; done'
# New, TLSv1.2, Cipher is ECDHE-RSA-AES256-GCM-SHA384
# New, TLSv1.3, Cipher is TLS_AES_256_GCM_SHA384

# 7. Or port-forward and test from your machine
k -n exercise-30 port-forward svc/secure-web 8443:443 &
echo | openssl s_client -connect localhost:8443 -tls1_2 2>/dev/null | grep "^New"
curl -k --tlsv1.2 --tls-max 1.2 https://localhost:8443
curl -k --tlsv1.3 https://localhost:8443
```

</details>
