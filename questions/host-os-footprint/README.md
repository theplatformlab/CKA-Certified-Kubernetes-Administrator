# Remove an unneeded service from a node

**Context:** `kubectl config use-context {{CONTEXT}}`

On node `{{NODE_W1}}` (`ssh {{NODE_W1}}`), a service listens on TCP port `{{PORT}}`. The node doesn't need it.

1. Find the process that listens on the port and the package it comes from. Write the package name into `{{WORKDIR}}/package.txt` on your exam host.
2. Stop the service and disable it, so it doesn't start again on boot.
3. Remove the package.

Nothing may listen on port `{{PORT}}` afterwards. The node must stay `Ready`.

## Hints

- `ss -ltnp` (or `netstat -ltnp`) shows each listening port with the owning process. `systemctl status <pid>` shows the unit that process belongs to.
- `dpkg -S <path of the binary>` names the package that installed a file. `ls -l /proc/<pid>/exe` shows the path of a running binary.
- Some services are socket-activated: systemd itself holds the port open and starts the service on the first connection. Then the `.socket` unit has to be stopped and disabled too.

## Solution

```bash
k config use-context {{CONTEXT}}
ssh {{NODE_W1}}
ss -ltnp | grep ':{{PORT}} '
# LISTEN 0  4096  0.0.0.0:{{PORT}}  0.0.0.0:*  users:(("{{PKG}}",pid=1234,fd=4) ...)
systemctl status 1234 | head -3          # the unit, e.g. {{PKG}}.service
dpkg -S "$(readlink /proc/1234/exe)"     # {{PKG}}: /usr/sbin/{{PKG}}
systemctl list-units --all | grep {{PKG}}   # a {{PKG}}.socket too?
systemctl disable --now {{PKG}}.service     # and {{PKG}}.socket if there is one
apt-get purge -y {{PKG}}
ss -ltn | grep ':{{PORT}} '              # nothing
exit

echo {{PKG}} > {{WORKDIR}}/package.txt
```

Every service you don't need is attack surface. It's also code that needs patches. `apt-get remove` keeps the configuration files, while `purge` removes them too. For a socket-activated service like `rpcbind`, stopping only `rpcbind.service` is not enough: systemd keeps listening on `rpcbind.socket` and starts the service again on the next connection.
