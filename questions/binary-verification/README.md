# Verify Kubernetes binaries against release checksums

**Context:** `kubectl config use-context {{CONTEXT}}`

On node `{{NODE_CP}}` (`ssh {{NODE_CP}}`), the directory `/opt/k8s-binaries` contains Kubernetes binaries that are supposed to come from the official release. The release's sha512 checksums are in `/root/release.sha512`.

1. Find every binary in `/opt/k8s-binaries` whose checksum doesn't match the release. Write their file names (one per line) into `{{WORKDIR}}/tampered.txt` on your exam host.
2. Delete those binaries from `/opt/k8s-binaries`. Keep the others.

## Hints

- `sha512sum <file>` prints the checksum. `sha512sum -c <checksum file>` compares all of them at once and prints `OK` or `FAILED` per file.
- The file names in `/root/release.sha512` are relative, so run the comparison inside `/opt/k8s-binaries`.
- Upstream publishes the same checksums at `https://dl.k8s.io/<version>/bin/linux/amd64/<binary>.sha512`.

## Solution

```bash
k config use-context {{CONTEXT}}
ssh {{NODE_CP}}
cd /opt/k8s-binaries
sha512sum -c /root/release.sha512
# kube-apiserver: OK
# kube-scheduler: FAILED      <- for example
# ...
# sha512sum: WARNING: 1 computed checksum did NOT match
rm kube-scheduler                # every FAILED one
exit

echo kube-scheduler > {{WORKDIR}}/tampered.txt     # one line per FAILED binary
```

Without a checksum file, compare one binary at a time: `sha512sum kubelet` and the published value, for example `curl -sL https://dl.k8s.io/v1.35.1/bin/linux/amd64/kubelet.sha512`. A modified binary can still run normally, so the checksum is the only way to tell. Here the binaries that failed were `{{TAMPERED}}`.
