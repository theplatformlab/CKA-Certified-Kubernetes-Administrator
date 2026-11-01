# Build an image and run it in the cluster

**Context:** `kubectl config use-context {{CONTEXT}}`

The directory `{{WORKDIR}}/greeter` contains a `Dockerfile` and the page it serves. Build tools on this host: `docker` (use `podman` instead if you prefer and it is installed).

1. Build an image from `{{WORKDIR}}/greeter` and tag it `registry.local/greeter:{{VER}}`. Do not change the files in the directory.
2. Save the image as a tarball to `{{WORKDIR}}/greeter-{{VER}}.tar`.
3. The registry `registry.local` does not exist. Make the image available on every node of cluster `{{CLUSTER}}` by loading the tarball: `kind load image-archive <file> --name {{CLUSTER}}`.
4. Create a Deployment `greeter` in namespace `build-pipeline` with 2 replicas that runs the image. The nodes must never try to pull it from the registry.

The pods must serve the page from the Dockerfile on port 8080.

## Hints

- `docker build -t <name:tag> <dir>` (or `podman build`); `docker images` shows the result.
- `docker save -o <file> <name:tag>` writes the tarball (`podman save -o` works the same way).
- An image that is not `:latest` defaults to `imagePullPolicy: IfNotPresent`; set it explicitly (`IfNotPresent` or `Never`) to be sure. `ErrImagePull` means the node doesn't have the image.

## Solution

```bash
k config use-context {{CONTEXT}}
cd {{WORKDIR}}/greeter
cat Dockerfile                                   # busybox httpd on port 8080
docker build -t registry.local/greeter:{{VER}} .     # or: podman build -t ...
docker save -o {{WORKDIR}}/greeter-{{VER}}.tar registry.local/greeter:{{VER}}
tar -tf {{WORKDIR}}/greeter-{{VER}}.tar | head        # manifest.json, blobs/...

kind load image-archive {{WORKDIR}}/greeter-{{VER}}.tar --name {{CLUSTER}}
ssh {{NODE_W1}} crictl images | grep greeter      # on every node

k -n build-pipeline create deployment greeter --image=registry.local/greeter:{{VER}} --replicas=2 \
  --dry-run=client -o yaml > greeter.yaml
```

```yaml
# greeter.yaml, container part
      containers:
      - name: greeter
        image: registry.local/greeter:{{VER}}
        imagePullPolicy: IfNotPresent      # or Never
```

```bash
k apply -f greeter.yaml
k -n build-pipeline rollout status deploy greeter
k -n build-pipeline exec deploy/greeter -- wget -qO- localhost:8080   # greeter {{VER}} build ...
```

Use a fully qualified name: `docker build -t greeter:{{VER}}` stores `docker.io/library/greeter:{{VER}}`, while `podman build` stores `localhost/greeter:{{VER}}`, and the pod spec has to match exactly what the node has. `kind load docker-image` loads straight from the docker daemon; the task asks for the tarball because that is what you hand over on a real exam (`podman save` defaults to the same docker-archive format; `--format oci-archive` works as well).
