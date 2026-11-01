# Generate SBOMs for an image

**Context:** `kubectl config use-context {{CONTEXT}}`

`trivy` is installed on node `{{NODE_CP}}` (`ssh {{NODE_CP}}`). Create a Software Bill of Materials (SBOM) for image `{{IMAGE}}`:

1. In SPDX JSON format, saved as `{{WORKDIR}}/sbom.spdx.json` on your exam host.
2. In CycloneDX format, saved as `{{WORKDIR}}/sbom.cdx.json` on your exam host.
3. According to the SBOM, which version of the package `{{PKG}}` does the image contain? Write only the version into `{{WORKDIR}}/version.txt`.

## Hints

- `trivy image --format <format> --output <file> <image>`. `trivy image --help` lists the formats: `spdx`, `spdx-json`, `cyclonedx`, ...
- The files are needed on your exam host. Either create them on the node and copy the content, or redirect the output of `ssh {{NODE_CP}} 'trivy ...'` into the file.
- In SPDX JSON the packages are in `.packages[]` (`name`, `versionInfo`). In CycloneDX they are in `.components[]` (`name`, `version`).

## Solution

```bash
k config use-context {{CONTEXT}}
ssh {{NODE_CP}} 'trivy image -q --format spdx-json {{IMAGE}}' > {{WORKDIR}}/sbom.spdx.json
ssh {{NODE_CP}} 'trivy image -q --format cyclonedx {{IMAGE}}' > {{WORKDIR}}/sbom.cdx.json

jq -r '.packages[] | select(.name == "{{PKG}}") | .versionInfo' {{WORKDIR}}/sbom.spdx.json
jq -r '.components[] | select(.name == "{{PKG}}") | .version' {{WORKDIR}}/sbom.cdx.json     # the same version
jq -r '.packages[] | select(.name == "{{PKG}}") | .versionInfo' {{WORKDIR}}/sbom.spdx.json > {{WORKDIR}}/version.txt
```

Without `jq`, `grep -A3 '"name": "{{PKG}}"' {{WORKDIR}}/sbom.cdx.json` works too. trivy writes its log messages to stderr, so only the SBOM ends up in the redirected file (`-q` silences the log completely). An SBOM can also be scanned later, without the image: `trivy sbom sbom.cdx.json` reports the known vulnerabilities of the listed packages.
