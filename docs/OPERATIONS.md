# Operations

## Install

`install.sh` installs `mtg` `2.2.8` by default. Use `--mtg-version <VERSION>` only when you
intentionally want to test or pin a different release.

Standard mode:

```bash
sudo ./scripts/install.sh --mode standard --host-ip <IP> --port 8443
```

FakeTLS mode (single-host, nginx on same server):

```bash
sudo ./scripts/install.sh --mode faketls --host-ip <IP> --port 443 --domain <DOMAIN> \
  --local-tls-proxy nginx --local-tls-port 4443
```

FakeTLS mode (dedicated IP, web server elsewhere):

```bash
sudo ./scripts/install.sh --mode faketls --host-ip <IP> --port 443 --domain <DOMAIN>
```

## Status

```bash
sudo systemctl status mtg --no-pager
ss -ltnp | grep -E ':(443|8443) '
```

## Doctor

```bash
sudo mtg doctor /etc/mtg/config.toml
```

In a single-host FakeTLS setup, the SNI-DNS check can report that the domain resolves to
`127.0.0.1`. That is expected when `/etc/hosts` intentionally points the FakeTLS domain to the
local TLS endpoint. Telegram DC connectivity and fronting-domain reachability should still pass.

## Logs

```bash
sudo journalctl -u mtg -f --no-pager
```

## Current secret

```bash
sudo cat /etc/mtg/secret
```

## Current config

```bash
sudo cat /etc/mtg/config.toml
```

## Restart

```bash
sudo systemctl restart mtg
```

## Secret rotation

By default, rerunning `install.sh` keeps the existing secret. It rotates automatically only when
the mode changes between `standard` and `faketls`, when the FakeTLS domain changes, when no secret
exists, or when `--rotate-secret` is passed. To rotate it explicitly:

```bash
sudo ./scripts/install.sh --mode standard --host-ip <IP> --port 8443 --rotate-secret
```

After rotation, share the new link from the output with all users.

## Proxy link

The link is printed at the end of `install.sh`. To regenerate it manually:

```bash
SECRET="$(sudo cat /etc/mtg/secret)"
IP="<IP>"
DOMAIN="<DOMAIN>" # optional; use for FakeTLS links
PORT="443"
SERVER="${DOMAIN:-$IP}"
echo "tg://proxy?server=${SERVER}&port=${PORT}&secret=${SECRET}"
echo "https://t.me/proxy?server=${SERVER}&port=${PORT}&secret=${SECRET}"
```

## Rollback

Service file backups are stored as:

```text
/etc/systemd/system/mtg.service.bak.<timestamp>
```

If local TLS helper was used, uninstall also removes the added `127.0.0.1:443` nginx listen
and the `/etc/hosts` domain entry. If the state file is missing, uninstall attempts to recover the
FakeTLS domain from the existing secret and remove legacy helper changes. Backups are also created
for:

```text
/etc/hosts.bak.<timestamp>
/etc/nginx/sites-enabled/<site>.bak.<timestamp>
```

## Uninstall

```bash
sudo ./scripts/uninstall.sh --port 443
```

## Release checks

```bash
bash -n scripts/install.sh
bash -n scripts/uninstall.sh
bash -n tests/install_test.sh
bash -n tests/uninstall_test.sh
bash tests/install_test.sh
bash tests/uninstall_test.sh
```

For single-host FakeTLS, also verify public DNS. If `mtg` listens only on IPv4, the proxy hostname
should not publish an `AAAA` record:

```bash
dig +short A <DOMAIN>
dig +short AAAA <DOMAIN>
```
