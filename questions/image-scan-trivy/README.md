# Scan Pod images with trivy and remove vulnerable Pods

**Context:** `kubectl config use-context {{CONTEXT}}`

The Pods in namespace `media-portal` run several different images. `trivy` is installed on node `{{NODE_CP}}` (`ssh {{NODE_CP}}`).

Scan the image of every Pod in `media-portal` with trivy. Delete every Pod whose image has at least one vulnerability of severity `CRITICAL`. Leave the other Pods running.

## Hints

- `k -n media-portal get pod -o custom-columns=NAME:.metadata.name,IMAGE:.spec.containers[*].image` lists the images.
- `trivy image --severity CRITICAL <image>` shows only critical findings. Add `-q` to hide the progress output, and `--scanners vuln` to skip the secret scan.
- trivy pulls the image from the registry itself. Its vulnerability database is already downloaded.

## Solution

```bash
k config use-context {{CONTEXT}}
k -n media-portal get pod -o custom-columns=NAME:.metadata.name,IMAGE:.spec.containers[*].image

ssh {{NODE_CP}}
for img in nginx:1.19-alpine httpd:2.4.39-alpine redis:7.4-alpine memcached:1.6-alpine python:3.9-alpine3.18; do
  echo "$img: $(trivy image -q --scanners vuln --severity CRITICAL --format json $img | grep -c '"Severity": "CRITICAL"')"
done
exit

# delete the Pods whose image has a count > 0, for example:
k -n media-portal delete pod <pod-with-nginx:1.19-alpine> <pod-with-httpd:2.4.39-alpine> ...
k -n media-portal get pod
```

The summary table trivy prints at the top of each scan (`Total: 9 (CRITICAL: 9)`) is enough too. With `--exit-code 1` trivy exits non-zero when it finds something of the given severity, which is handy in scripts and CI pipelines. Results change as new CVEs are published: an image without critical findings today can have some next month. That's why images are scanned continuously and not only at build time.
