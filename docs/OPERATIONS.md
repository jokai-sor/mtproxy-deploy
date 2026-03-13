# Operations

## Install

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

By default, rerunning `install.sh` keeps the existing secret. To rotate it explicitly:

```bash
sudo ./scripts/install.sh --mode standard --host-ip <IP> --port 8443 --rotate-secret
```

After rotation, share the new link from the output with all users.

## Proxy link

The link is printed at the end of `install.sh`. To regenerate it manually:

```bash
SECRET="$(sudo cat /etc/mtg/secret)"
IP="<IP>"
PORT="443"
echo "tg://proxy?server=${IP}&port=${PORT}&secret=${SECRET}"
echo "https://t.me/proxy?server=${IP}&port=${PORT}&secret=${SECRET}"
```

## Rollback

Service file backups are stored as:

```text
/etc/systemd/system/mtg.service.bak.<timestamp>
```

If local TLS helper was used, uninstall also removes the added `127.0.0.1:443` nginx listen
and the `/etc/hosts` domain entry. Backups are also created for:

```text
/etc/hosts.bak.<timestamp>
/etc/nginx/sites-enabled/<site>.bak.<timestamp>
```

## Uninstall

```bash
sudo ./scripts/uninstall.sh --port 443
```
