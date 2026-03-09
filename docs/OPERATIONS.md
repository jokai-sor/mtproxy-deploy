# Operations

## Install

Standard mode:

```bash
sudo ./scripts/install.sh --mode standard --host-ip <IP> --port 8443
```

FakeTLS mode:

```bash
sudo ./scripts/install.sh --mode faketls --host-ip <IP> --port 443 --domain <DOMAIN>
```

## Status

```bash
sudo systemctl status mtproxy --no-pager
ss -ltnp | grep -E ':(443|8443) '
```

## Logs

```bash
sudo journalctl -u mtproxy -f --no-pager
```

## Current secret

```bash
sudo cat /etc/mtproxy/secret
```

## Current service file

```bash
sudo systemctl cat mtproxy
```

## Restart

```bash
sudo systemctl restart mtproxy
```

## FakeTLS link generation

```bash
SECRET="$(sudo cat /etc/mtproxy/secret)"
DOMAIN="tg.example.com"
DOMAIN_HEX="$(printf '%s' "$DOMAIN" | xxd -ps -c 256)"
echo "tg://proxy?server=<IP>&port=443&secret=ee${SECRET}${DOMAIN_HEX}"
```

## Rollback

Service file backups are stored as:

```text
/etc/systemd/system/mtproxy.service.bak.<timestamp>
```

If local TLS helper was used, backups are also created for:

```text
/etc/hosts.bak.<timestamp>
/etc/nginx/sites-enabled/<site>.bak.<timestamp>
```

Restore example:

```bash
sudo cp /etc/systemd/system/mtproxy.service.bak.<timestamp> /etc/systemd/system/mtproxy.service
sudo systemctl daemon-reload
sudo systemctl restart mtproxy
```

## Uninstall

```bash
sudo ./scripts/uninstall.sh --port 443
```
