# Init container prepares content

**Context:** `kubectl config use-context {{CONTEXT}}`

In namespace `docs`, Service `content-server` publishes the page `/{{FILE}}` on port `80`. The backend needs a while after start-up before it answers.

Create a Deployment named `docs-site` in namespace `docs` with 1 replica and pod label `app=docs-site`:

1. An `emptyDir` volume named `content`.
2. An init container named `fetch`, image `busybox:1.37`, that mounts `content` at `/work`. It must wait until `http://content-server/{{FILE}}` can be downloaded and then save the page as `/work/index.html`.
3. A container named `web`, image `nginx:1.28`, that mounts `content` at `/usr/share/nginx/html`.

Then expose the Deployment as a ClusterIP Service named `docs-site` on port `80`, so that `http://docs-site.docs` returns the fetched page.

## Hints

- `k create deployment ... $do` gives the skeleton. Add `volumes`, `initContainers` and `volumeMounts` by hand. `k explain pod.spec.initContainers` lists the fields.
- busybox `wget -O <file> <url>` saves a page. Retry it in a shell loop: `until wget ...; do sleep 2; done`.
- Init containers run to completion one after the other before the app containers start. A volume shared by both is how the init container hands over files.

## Solution

```bash
k config use-context {{CONTEXT}}
k -n docs create deployment docs-site --image=nginx:1.28 $do > docs-site.yaml
```

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: docs-site
  namespace: docs
spec:
  replicas: 1
  selector:
    matchLabels:
      app: docs-site
  template:
    metadata:
      labels:
        app: docs-site
    spec:
      volumes:
      - name: content
        emptyDir: {}
      initContainers:
      - name: fetch
        image: busybox:1.37
        command: ["sh", "-c", "until wget -q -T 3 -O /work/index.html http://content-server/{{FILE}}; do echo waiting; sleep 2; done"]
        volumeMounts:
        - name: content
          mountPath: /work
      containers:
      - name: web
        image: nginx:1.28
        volumeMounts:
        - name: content
          mountPath: /usr/share/nginx/html
```

```bash
k apply -f docs-site.yaml
k -n docs get pods -w                          # Init:0/1 -> PodInitializing -> Running
k -n docs expose deployment docs-site --port=80
k run t --rm -it --image=busybox:1.37 --restart=Never -- wget -qO- docs-site.docs
```

Without the retry loop the init container fails while the backend is still starting, and the pod sits in `Init:Error` / `Init:CrashLoopBackOff` with growing back-off. A failed `wget -O` can leave an empty file behind, so the loop must only end on success. The `emptyDir` lives as long as the pod, so the main container sees the file the init container wrote.
