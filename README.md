# mtproxy-deploy

[English](README.md) | [Русский](README.ru.md)

Operational deployment project for standalone Telegram MTProxy on Ubuntu.

`mtproxy-deploy` focuses on one job: install, run, and operate MTProxy cleanly on a VPS.

It uses [mtg](https://github.com/9seconds/mtg) — a Go-based MTProxy implementation that performs
a real TLS handshake relay, making fake-TLS work on all Telegram clients including Android.

## Scope

This project supports two deployment modes:

- `standard`: regular MTProxy on a chosen TCP port
- `faketls`: MTProxy TLS transport on `443` with a domain-backed FakeTLS handshake

This project does not manage:

- per-user accounts
- billing, quotas, or traffic accounting
- reverse-proxy multiplexing of multiple products on one `443`

## Requirements

- Ubuntu 24.04 or similar systemd-based distro
- root access
- `curl`, `xxd`, `ufw` (installed automatically by `install.sh`)
- for `faketls` mode:
  - a domain pointed to the server
  - dedicated public `443/tcp` for MTProxy
  - a TLS-capable endpoint for that domain that mtg can probe

`nginx` is not a project dependency. If you already have a local HTTPS service and want to reuse it
for a single-host FakeTLS setup, `mtproxy-deploy` can optionally patch that local service.

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

Optional single-host workaround for FakeTLS when you deliberately reuse a local HTTPS service
after moving the public website away from `443`:

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

This is an optional compatibility helper, not the primary architecture of the project.

## What install.sh does

1. Installs dependencies: `curl`, `xxd`, `ufw`
2. Downloads `mtg` `2.2.8` by default (auto-detects architecture; override with `--mtg-version`)
3. Generates an MTProxy secret via `mtg generate-secret`
4. Preserves the existing secret by default (use `--rotate-secret` to regenerate)
5. Writes `/etc/mtg/config.toml`
6. Creates `/etc/systemd/system/mtg.service`
7. Restarts `mtg` so binary, secret, and config changes are applied immediately
8. Opens the client TCP port in `ufw` if available
9. Prints ready-to-use Telegram links

## Project layout

```text
scripts/install.sh          Install or upgrade MTProxy
scripts/uninstall.sh        Remove MTProxy deployment
README.md                   English overview
README.ru.md                Russian overview
LICENSE                     MIT license
docs/OPERATIONS.md          Runtime operations and rollback
docs/FAKETLS.md             FakeTLS notes and caveats
tests/*.sh                  Shell regression tests for install/uninstall logic
```

## Telegram links

Standard:

```text
tg://proxy?server=<IP>&port=<PORT>&secret=<SECRET>
https://t.me/proxy?server=<IP>&port=<PORT>&secret=<SECRET>
```

FakeTLS:

```text
tg://proxy?server=<DOMAIN>&port=443&secret=<SECRET>
https://t.me/proxy?server=<DOMAIN>&port=443&secret=<SECRET>
```

(The FakeTLS secret already encodes the domain — `mtg generate-secret --hex <domain>` produces
the full `ee<secret><domain_hex>` string that goes directly into the link.)

## Notes

- `mtg` proxies the real TLS certificate from the domain endpoint. This means both iOS and Android
  Telegram clients work correctly with FakeTLS.
- For FakeTLS, avoid trying to hide multiple unrelated services behind the same public `443` unless
  you are deliberately building a more complex TCP-routing design.
- For a single-host FakeTLS setup, publish only an `A` record for the proxy hostname unless `mtg`
  also listens on IPv6. A public `AAAA` record that points to an unused IPv6 `443` can make clients
  appear connected while traffic does not flow correctly.
- If you need multi-product operational control, keep MTProxy separate from SOCKS5 tooling.
