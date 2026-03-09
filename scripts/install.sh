#!/usr/bin/env bash
set -euo pipefail

MODE="standard"
HOST_IP=""
DOMAIN=""
MTPROXY_PORT="8443"
MTPROXY_STATS_PORT="8888"
MTPROXY_WORKERS="1"
MTPROXY_DIR="/opt/MTProxy"
MTPROXY_SECRET_FILE="/etc/mtproxy/secret"
MTPROXY_SERVICE_FILE="/etc/systemd/system/mtproxy.service"
LOCAL_TLS_PROXY=""
LOCAL_TLS_PORT=""
NGINX_SITE="/etc/nginx/sites-enabled/webdock"

usage() {
  cat <<USAGE
Usage:
  sudo ./scripts/install.sh --mode standard --host-ip <IP> [--port 8443]
  sudo ./scripts/install.sh --mode faketls --host-ip <IP> --port 443 --domain <DOMAIN>

Options:
  --mode standard|faketls
  --host-ip IP
  --port PORT
  --stats-port PORT
  --workers N
  --domain DOMAIN
  --local-tls-proxy nginx
  --local-tls-port PORT
  --nginx-site PATH
USAGE
}

backup_file() {
  local file="$1"
  if [[ -f "$file" ]]; then
    cp "$file" "$file.bak.$STAMP"
  fi
}

hex_domain() {
  printf '%s' "$1" | xxd -ps -c 256
}

patch_nginx_for_local_tls() {
  local site="$1"
  local public_port="$2"
  if [[ ! -f "$site" ]]; then
    echo "nginx site not found: $site" >&2
    exit 1
  fi
  backup_file "$site"
  python3 - "$site" "$public_port" <<'PY'
from pathlib import Path
import sys
site = Path(sys.argv[1])
port = sys.argv[2]
text = site.read_text()
line_v4 = f"    listen {port} ssl;"
if line_v4 not in text:
    raise SystemExit(f"nginx site does not contain expected listen line for port {port}")
insert = f"{line_v4} # managed by Certbot\n    listen 127.0.0.1:443 ssl;\n"
if 'listen 127.0.0.1:443 ssl;' not in text:
    text = text.replace(f"{line_v4} # managed by Certbot\n", insert, 1)
site.write_text(text)
PY
  nginx -t
}

patch_hosts_for_domain() {
  local domain="$1"
  backup_file /etc/hosts
  if ! grep -qE "^[[:space:]]*127\.0\.0\.1[[:space:]].*\b${domain//./\.}\b" /etc/hosts; then
    printf '127.0.0.1 %s\n' "$domain" >> /etc/hosts
  fi
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --mode) MODE="$2"; shift 2 ;;
    --host-ip) HOST_IP="$2"; shift 2 ;;
    --port) MTPROXY_PORT="$2"; shift 2 ;;
    --stats-port) MTPROXY_STATS_PORT="$2"; shift 2 ;;
    --workers) MTPROXY_WORKERS="$2"; shift 2 ;;
    --domain) DOMAIN="$2"; shift 2 ;;
    --local-tls-proxy) LOCAL_TLS_PROXY="$2"; shift 2 ;;
    --local-tls-port) LOCAL_TLS_PORT="$2"; shift 2 ;;
    --nginx-site) NGINX_SITE="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "unknown argument: $1" >&2; usage; exit 1 ;;
  esac
done

if [[ "${EUID}" -ne 0 ]]; then
  echo "run as root: sudo ./scripts/install.sh ..." >&2
  exit 1
fi

if [[ -z "$HOST_IP" ]]; then
  HOST_IP="$(hostname -I | awk '{print $1}')"
fi

if [[ "$MODE" != "standard" && "$MODE" != "faketls" ]]; then
  echo "invalid mode: $MODE" >&2
  exit 1
fi

if [[ "$MODE" == "faketls" ]]; then
  if [[ -z "$DOMAIN" ]]; then
    echo "--domain is required in faketls mode" >&2
    exit 1
  fi
  if [[ "$MTPROXY_PORT" != "443" ]]; then
    echo "faketls mode should use --port 443" >&2
    exit 1
  fi
  MTPROXY_WORKERS="0"
fi

STAMP="$(date +%F-%H%M%S)"

apt-get update
apt-get install -y git curl build-essential libssl-dev zlib1g-dev ufw

rm -rf "$MTPROXY_DIR"
git clone https://github.com/mtProtoProxy/MTProxy-official "$MTPROXY_DIR"

perl -0pi -e 's/^CFLAGS = (.*)$/CFLAGS = -fcommon $1/m' "$MTPROXY_DIR/Makefile"
perl -0pi -e 's/assert \(!\(p & 0xffff0000\)\);\n    PID\.pid = p;/PID.pid = (unsigned short)(p \& 0xffff);/' "$MTPROXY_DIR/common/pid.c"

make -C "$MTPROXY_DIR" clean
make -C "$MTPROXY_DIR"

cd "$MTPROXY_DIR/objs/bin"
curl -fsSL https://core.telegram.org/getProxySecret -o proxy-secret
curl -fsSL https://core.telegram.org/getProxyConfig -o proxy-multi.conf

install -d -m 0755 "$(dirname "$MTPROXY_SECRET_FILE")"
head -c 16 /dev/urandom | xxd -ps > "$MTPROXY_SECRET_FILE"
SECRET="$(tr -d '\n' < "$MTPROXY_SECRET_FILE")"

if [[ "$MODE" == "standard" ]]; then
  EXEC_START="$MTPROXY_DIR/objs/bin/mtproto-proxy -u nobody -p $MTPROXY_STATS_PORT -H $MTPROXY_PORT -S $SECRET --aes-pwd $MTPROXY_DIR/objs/bin/proxy-secret $MTPROXY_DIR/objs/bin/proxy-multi.conf -M $MTPROXY_WORKERS"
else
  EXEC_START="$MTPROXY_DIR/objs/bin/mtproto-proxy -u nobody -p $MTPROXY_STATS_PORT -H $MTPROXY_PORT -S $SECRET -D $DOMAIN --address $HOST_IP --aes-pwd $MTPROXY_DIR/objs/bin/proxy-secret $MTPROXY_DIR/objs/bin/proxy-multi.conf -M 0"
fi

backup_file "$MTPROXY_SERVICE_FILE"
cat > "$MTPROXY_SERVICE_FILE" <<UNIT
[Unit]
Description=MTProxy Telegram Proxy
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
WorkingDirectory=$MTPROXY_DIR/objs/bin
ExecStart=$EXEC_START
Restart=on-failure
RestartSec=3

[Install]
WantedBy=multi-user.target
UNIT

if [[ "$MODE" == "faketls" && "$LOCAL_TLS_PROXY" == "nginx" && -n "$LOCAL_TLS_PORT" ]]; then
  patch_nginx_for_local_tls "$NGINX_SITE" "$LOCAL_TLS_PORT"
  patch_hosts_for_domain "$DOMAIN"
fi

systemctl daemon-reload
systemctl enable --now mtproxy
if command -v ufw >/dev/null 2>&1; then
  ufw allow "$MTPROXY_PORT"/tcp >/dev/null 2>&1 || true
fi

if [[ "$MODE" == "standard" ]]; then
  CLIENT_SECRET="$SECRET"
else
  CLIENT_SECRET="ee${SECRET}$(hex_domain "$DOMAIN")"
fi

echo
echo "mode: $MODE"
echo "host_ip: $HOST_IP"
echo "port: $MTPROXY_PORT"
if [[ -n "$DOMAIN" ]]; then
  echo "domain: $DOMAIN"
fi
echo
echo "mtproxy_status:"
systemctl --no-pager --full status mtproxy | sed -n '1,18p'
echo
echo "telegram_link:"
echo "tg://proxy?server=$HOST_IP&port=$MTPROXY_PORT&secret=$CLIENT_SECRET"
echo "https://t.me/proxy?server=$HOST_IP&port=$MTPROXY_PORT&secret=$CLIENT_SECRET"
