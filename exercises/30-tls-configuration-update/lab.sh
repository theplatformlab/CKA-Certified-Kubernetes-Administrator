# shellcheck shell=bash
# Exercise 30 — TLS configuration update. Sourced by scripts/lab.sh.
# Setup deploys an nginx that terminates TLS (self-signed cert) and only allows TLSv1.3.
# The task is to add TLSv1.2; the check handshakes with openssl from a throwaway pod.
LAB_CLUSTER=practice
NS="${ITEM_NS:-exercise-30}"

_gen_cert() {
  local dir="$1" subj="/CN=secure-web.${NS}.svc"
  local args=(req -x509 -nodes -newkey rsa:2048 -days 365 -subj "$subj"
              -addext "subjectAltName=DNS:secure-web,DNS:secure-web.${NS}.svc,DNS:secure-web.${NS}.svc.cluster.local")
  if command -v openssl >/dev/null 2>&1; then
    openssl "${args[@]}" -keyout "$dir/tls.key" -out "$dir/tls.crt" 2>/dev/null
  else
    docker run --rm -v "$dir:/out" --entrypoint openssl nginx:1.28 "${args[@]}" \
      -keyout /out/tls.key -out /out/tls.crt 2>/dev/null
  fi
}

lab_setup() {
  kc create namespace "$NS" --dry-run=client -o yaml | kc apply -f -
  if ! kc get secret secure-web-tls -n "$NS" >/dev/null 2>&1; then
    local tmp
    tmp="$(mktemp -d)"
    _gen_cert "$tmp"
    kc create secret tls secure-web-tls -n "$NS" --cert="$tmp/tls.crt" --key="$tmp/tls.key"
    rm -rf "$tmp"
  fi
  local existed=false
  kc get deployment secure-web -n "$NS" >/dev/null 2>&1 && existed=true
  kc apply -f - <<EOF
apiVersion: v1
kind: ConfigMap
metadata:
  name: secure-web-config
  namespace: ${NS}
data:
  default.conf: |
    server {
        listen 443 ssl;
        server_name secure-web;

        ssl_certificate     /etc/nginx/tls/tls.crt;
        ssl_certificate_key /etc/nginx/tls/tls.key;
        ssl_protocols       TLSv1.3;

        location / {
            default_type text/plain;
            return 200 "secure-web OK\n";
        }
    }
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: secure-web
  namespace: ${NS}
spec:
  replicas: 1
  selector:
    matchLabels:
      app: secure-web
  template:
    metadata:
      labels:
        app: secure-web
    spec:
      containers:
      - name: nginx
        image: nginx:1.28
        ports:
        - name: https
          containerPort: 443
        volumeMounts:
        - name: config
          mountPath: /etc/nginx/conf.d
        - name: tls
          mountPath: /etc/nginx/tls
          readOnly: true
      volumes:
      - name: config
        configMap:
          name: secure-web-config
      - name: tls
        secret:
          secretName: secure-web-tls
---
apiVersion: v1
kind: Service
metadata:
  name: secure-web
  namespace: ${NS}
spec:
  selector:
    app: secure-web
  ports:
  - name: https
    port: 443
    targetPort: 443
EOF
  # Re-running setup resets the config: restart so the pod really serves TLSv1.3 only again.
  [[ "$existed" == true ]] && kc rollout restart deployment secure-web -n "$NS"
  kc rollout status deployment secure-web -n "$NS" --timeout=120s
}

# _tls_probe — handshake with secure-web using TLS 1.2 and 1.3 from a pod with openssl.
# Prints "tls12=<protocol|fail> tls13=<protocol|fail>".
_tls_probe() {
  local host="secure-web.${NS}.svc.cluster.local:443"
  # "New, TLSv1.x, Cipher is ..." names the negotiated protocol; "(NONE)" means the handshake failed.
  local t='v=$(echo | openssl s_client -connect '"$host"' $1 2>/dev/null | sed -n "s/^New, \(TLSv[0-9.]*\), Cipher is.*/\1/p" | head -1); echo "$2=${v:-fail}"'
  timeout 90 kubectl --context "$CTX" -n "$NS" run "tls-probe-$RANDOM$RANDOM" --image=nginx:1.28 \
    --restart=Never --quiet --rm -i --pod-running-timeout=60s --command -- \
    sh -c "sleep 2; t() { $t; }; t -tls1_2 tls12; t -tls1_3 tls13" </dev/null 2>/dev/null
}

lab_check() {
  local protos out
  protos="$(jp -n $NS cm secure-web-config '{.data.default\.conf}' | sed -n 's/^ *ssl_protocols *\([^;]*\);.*/\1/p' | head -1)"
  check_match "ConfigMap secure-web-config: ssl_protocols enables TLSv1.2" "$protos" "(^| )TLSv1\.2( |$)"
  check_match "ConfigMap secure-web-config: ssl_protocols still enables TLSv1.3" "$protos" "(^| )TLSv1\.3( |$)"
  check_not "ConfigMap secure-web-config: no older protocols (TLSv1, TLSv1.1)" \
    grep -Eq '(^| )TLSv1(\.1)?( |$)' <<<"$protos"
  check_eq "Deployment secure-web has 1 ready pod" \
    "$(jp -n $NS deploy secure-web '{.spec.replicas}/{.status.readyReplicas}')" "1/1"

  out="$(_tls_probe | tr "\n" " ")"
  check_match "secure-web accepts a TLS 1.2 handshake (pod restarted with the new config)" "$out" "tls12=TLSv1\.2( |$)"
  check_match "secure-web still accepts a TLS 1.3 handshake" "$out" "tls13=TLSv1\.3( |$)"
}

lab_cleanup() {
  kc delete namespace "$NS" --ignore-not-found --wait=false
}
