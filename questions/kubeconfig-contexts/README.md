# Read a kubeconfig file

**Context:** `kubectl config use-context {{CONTEXT}}`

The platform team handed you the kubeconfig file `{{WORKDIR}}/fleet.kubeconfig`. Its clusters are not reachable from your host; you only need to read the file. Do not change it.

1. Write the names of all contexts defined in the file, one per line, into `{{WORKDIR}}/contexts.txt`.
2. Write the name of the file's current context into `{{WORKDIR}}/current-context.txt`.
3. Find the user that context `{{CERT_CTX}}` uses. Write that user's client certificate, decoded to PEM (`-----BEGIN CERTIFICATE-----` ...), into `{{WORKDIR}}/client.crt`.

## Hints

- Every `kubectl config` subcommand accepts `--kubeconfig <file>` and then works on that file instead of your own kubeconfig.
- `k config get-contexts -o name` prints only the names, `k config current-context` the current one.
- Embedded certificates are base64 in `client-certificate-data`. `k config view` hides them unless you add `--raw`; a jsonpath filter like `{.users[?(@.name=="...")].user.client-certificate-data}` picks one user, `base64 -d` decodes it.

## Solution

```bash
k config use-context {{CONTEXT}}
KCFG={{WORKDIR}}/fleet.kubeconfig
k config get-contexts --kubeconfig $KCFG     # * marks the current context, AUTHINFO is the user
k config get-contexts -o name --kubeconfig $KCFG > {{WORKDIR}}/contexts.txt
k config current-context --kubeconfig $KCFG > {{WORKDIR}}/current-context.txt    # {{CURRENT_CTX}}

KUSER=$(k config view --kubeconfig $KCFG -o jsonpath='{.contexts[?(@.name=="{{CERT_CTX}}")].context.user}')
echo $KUSER
k config view --raw --kubeconfig $KCFG \
  -o jsonpath="{.users[?(@.name==\"$KUSER\")].user.client-certificate-data}" | base64 -d > {{WORKDIR}}/client.crt
openssl x509 -in {{WORKDIR}}/client.crt -noout -subject     # subject=CN=<user>, O=fleet
```

A kubeconfig has three lists: `clusters` (server and CA), `users` (credentials) and `contexts`, which only pair a cluster with a user and a default namespace by name. The context name is free text, so `{{CERT_CTX}}` does not have to match the user's name; look the user up in the context. Without `--kubeconfig`, every command reads your own kubeconfig (`$KUBECONFIG` or `~/.kube/config`) and prints the wrong contexts. Without `--raw`, `k config view` prints `DATA+OMITTED` instead of the certificate.
