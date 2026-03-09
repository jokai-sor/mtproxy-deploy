# mtproxy-deploy

Operational deployment project for standalone Telegram MTProxy on Ubuntu.

`mtproxy-deploy` is intentionally separate from `proxyctl` and Dante SOCKS5. It focuses on one job: build, install, run, and operate MTProxy cleanly on a VPS.

## Scope

This project supports two deployment modes:

- `standard`: regular MTProxy on a chosen TCP port
- `faketls`: MTProxy TLS transport on `443` with a domain-backed FakeTLS handshake

This project does not manage:

- Dante SOCKS5
- per-user accounts
- billing, quotas, or traffic accounting
- reverse-proxy multiplexing of multiple products on one `443`

## Requirements

- Ubuntu 24.04 or similar systemd-based distro
- root access
- `ufw` installed if you want firewall automation
- for `faketls` mode:
  - a domain pointed to the server
  - local HTTPS endpoint that can answer for that domain
  - dedicated public `443/tcp` for MTProxy

## Quick start

Standard MTProxy on `8443`:

```bash
sudo ./scripts/install.sh \
  --mode standard \
  --host-ip 203.0.113.10 \
  --port 8443
```

FakeTLS MTProxy on `443`:

```bash
sudo ./scripts/install.sh \
  --mode faketls \
  --host-ip 203.0.113.10 \
  --port 443 \
  --domain tg.example.com
```

Optional local TLS check helper for FakeTLS when your public web server is moved away from `443` and available locally on another HTTPS port:

```bash
sudo ./scripts/install.sh \
  --mode faketls \
  --host-ip 203.0.113.10 \
  --port 443 \
  --domain tg.example.com \
  --local-tls-proxy nginx \
  --local-tls-port 4443
```

That helper adds:

- `127.0.0.1:443` listener to the chosen local TLS server config
- `127.0.0.1 <domain>` to `/etc/hosts`

Use it only if you understand the tradeoff and control that host locally.

## What install.sh does

1. Installs build dependencies
2. Clones official MTProxy upstream
3. Applies two Ubuntu-compatibility patches observed on this environment:
- `-fcommon` in `Makefile`
- PID truncation patch in `common/pid.c`
4. Downloads `proxy-secret` and `proxy-multi.conf`
5. Generates MTProxy secret
6. Creates `/etc/systemd/system/mtproxy.service`
7. Opens the client TCP port in `ufw` if available
8. Prints ready-to-use Telegram links

## Project layout

```text
scripts/install.sh          Install or upgrade MTProxy
scripts/uninstall.sh        Remove MTProxy deployment
README.md                   English overview
README.ru.md                Russian overview
LICENSE                     MIT license
docs/OPERATIONS.md          Runtime operations and rollback
docs/FAKETLS.md             FakeTLS notes and caveats
```

## Telegram links

Standard:

```text
tg://proxy?server=<IP>&port=<PORT>&secret=<SECRET>
https://t.me/proxy?server=<IP>&port=<PORT>&secret=<SECRET>
```

FakeTLS:

```text
tg://proxy?server=<IP>&port=443&secret=ee<SECRET><DOMAIN_HEX>
https://t.me/proxy?server=<IP>&port=443&secret=ee<SECRET><DOMAIN_HEX>
```

## Notes

- Upstream `MTProxy` is specialized software. Keep the deployment simple.
- For FakeTLS, avoid trying to hide multiple unrelated services behind the same public `443` unless you are deliberately building a more complex TCP-routing design.
- If you need multi-product operational control, keep MTProxy separate from SOCKS5 tooling.
