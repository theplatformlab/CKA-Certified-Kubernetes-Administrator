# shellcheck shell=bash
# Init container that fetches content for the main container. Sourced by scripts/lab.sh.
LAB_CLUSTER=practice
NS=docs

lab_params() {
  echo "FILE=$(pick release-notes.html handbook.html guide-v2.html changelog.html)"
  echo "BUILD=$(rand_suffix 8)"
}

lab_setup() {
  ensure_ns "$NS"
  # content-server only becomes ready after ~20s, like a slow backend.
  kc apply -f - <<YAML
apiVersion: apps/v1
kind: Deployment
metadata:
  name: content-server
  namespace: $NS
spec:
  replicas: 1
  selector:
    matchLabels:
      app: content-server
  template:
    metadata:
      labels:
        app: content-server
    spec:
      containers:
      - name: server
        image: busybox:1.37
        command: ["sh", "-c", "sleep 20; mkdir -p /www && echo '<h1>docs build $BUILD</h1>' > /www/$FILE && exec httpd -f -p 80 -h /www"]
        readinessProbe:
          tcpSocket:
            port: 80
          periodSeconds: 3
---
apiVersion: v1
kind: Service
metadata:
  name: content-server
  namespace: $NS
spec:
  selector:
    app: content-server
  ports:
  - port: 80
YAML
}

_t='{.spec.template.spec'

lab_check() {
  check_gate "Deployment docs-site exists" exists -n $NS deploy docs-site
  check_eq "Init container fetch uses busybox:1.37" \
    "$(jp -n $NS deploy docs-site "$_t.initContainers[0].name} $_t.initContainers[0].image}")" "fetch busybox:1.37"
  check_eq "Volume content is an emptyDir" \
    "$(jp -n $NS deploy docs-site "$_t.volumes[?(@.name==\"content\")].emptyDir}" | sed 's/^$/none/; s/^{.*}$/ok/')" "ok"
  check_eq "fetch mounts content at /work" \
    "$(jp -n $NS deploy docs-site "$_t.initContainers[0].volumeMounts[?(@.name==\"content\")].mountPath}")" "/work"
  check_eq "Container web runs nginx:1.28 and mounts content at /usr/share/nginx/html" \
    "$(jp -n $NS deploy docs-site "$_t.containers[?(@.name==\"web\")].image} $_t.containers[?(@.name==\"web\")].volumeMounts[?(@.name==\"content\")].mountPath}")" \
    "nginx:1.28 /usr/share/nginx/html"
  check_eq "Deployment docs-site has 1 ready replica" "$(jp -n $NS deploy docs-site '{.status.readyReplicas}')" "1"
  check_contains "http://docs-site.$NS serves the fetched $FILE" \
    "$(probe default - "wget -qO- -T 5 http://docs-site.$NS")" "docs build $BUILD"
}

lab_cleanup() {
  kc delete namespace "$NS" --ignore-not-found --wait=false
}
