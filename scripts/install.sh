#!/usr/bin/env bash
set -euo pipefail

MODE="standard"
HOST_IP=""
DOMAIN=""
MTG_PORT="8443"
MTG_BINARY="/usr/local/bin/mtg"
MTG_CONFIG_DIR="/etc/mtg"
MTG_CONFIG="$MTG_CONFIG_DIR/config.toml"
MTG_SECRET_FILE="$MTG_CONFIG_DIR/secret"
MTG_SERVICE_FILE="/etc/systemd/system/mtg.service"
LOCAL_TLS_PROXY=""
LOCAL_TLS_PORT=""
NGINX_SITE="/etc/nginx/sites-enabled/webdock"
FAKETLS_STATE_FILE="$MTG_CONFIG_DIR/faketls.env"
ROTATE_SECRET="0"

usage() {
  cat <<USAGE
Usage:
  sudo ./scripts/install.sh --mode standard --host-ip <IP> [--port 8443]
  sudo ./scripts/install.sh --mode faketls --host-ip <IP> --port 443 --domain <DOMAIN>

Options:
  --mode standard|faketls
  --host-ip IP
  --port PORT
  --domain DOMAIN
  --local-tls-proxy nginx
  --local-tls-port PORT
  --nginx-site PATH
  --rotate-secret
USAGE
}

hex_domain() {
  printf '%s' "$1" | xxd -ps -c 256
}

ensure_config_dir() {
  install -d -m 0755 "$MTG_CONFIG_DIR"
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
needle = f"    listen {port} ssl; # managed by Certbot\n"
if needle not in text:
    raise SystemExit(f"nginx site does not contain expected listen line for port {port}")
insert = needle + "    listen 127.0.0.1:443 ssl;\n"
if 'listen 127.0.0.1:443 ssl;' not in text:
    text = text.replace(needle, insert, 1)
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

backup_file() {
  local file="$1"
  if [[ -f "$file" ]]; then
    local dir base backup_dir
    dir="$(dirname "$file")"
    base="$(basename "$file")"
    backup_dir="$dir"
    if [[ "$dir" == "/etc/nginx/sites-enabled" ]]; then
      backup_dir="/etc/nginx"
    fi
    cp "$file" "$backup_dir/$base.bak.$STAMP"
  fi
}

write_faketls_state() {
  ensure_config_dir
  cat > "$FAKETLS_STATE_FILE" <<STATE
MODE=$MODE
DOMAIN=$DOMAIN
LOCAL_TLS_PROXY=$LOCAL_TLS_PROXY
LOCAL_TLS_PORT=$LOCAL_TLS_PORT
NGINX_SITE=$NGINX_SITE
STATE
}

clear_faketls_state() {
  rm -f "$FAKETLS_STATE_FILE"
}

install_mtg() {
  local arch
  arch="$(uname -m)"
  case "$arch" in
    x86_64)  arch="amd64" ;;
    aarch64) arch="arm64" ;;
    armv7l)  arch="arm" ;;
    *) echo "unsupported architecture: $arch" >&2; exit 1 ;;
  esac

  local version
  version="$(curl -fsSL https://api.github.com/repos/9seconds/mtg/releases/latest \
    | grep '"tag_name"' | head -1 | sed 's/.*"v\([^"]*\)".*/\1/')"

  if [[ -z "$version" ]]; then
    echo "failed to detect latest mtg version" >&2
    exit 1
  fi

  echo "installing mtg v${version} (${arch})..."
  local url="https://github.com/9seconds/mtg/releases/download/v${version}/mtg-${version}-linux-${arch}.tar.gz"
  local tmpdir
  tmpdir="$(mktemp -d)"
  trap 'rm -rf "$tmpdir"' RETURN
  curl -fsSL "$url" | tar xz -C "$tmpdir"
  install -m 0755 "$tmpdir/mtg" "$MTG_BINARY"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --mode) MODE="$2"; shift 2 ;;
    --host-ip) HOST_IP="$2"; shift 2 ;;
    --port) MTG_PORT="$2"; shift 2 ;;
    --domain) DOMAIN="$2"; shift 2 ;;
    --local-tls-proxy) LOCAL_TLS_PROXY="$2"; shift 2 ;;
    --local-tls-port) LOCAL_TLS_PORT="$2"; shift 2 ;;
    --nginx-site) NGINX_SITE="$2"; shift 2 ;;
    --rotate-secret) ROTATE_SECRET="1"; shift ;;
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
  if [[ "$MTG_PORT" != "443" ]]; then
    echo "faketls mode should use --port 443" >&2
    exit 1
  fi
fi

STAMP="$(date +%F-%H%M%S)"

apt-get update -q
apt-get install -y -q curl xxd ufw

install_mtg
ensure_config_dir

if [[ -f "$MTG_SECRET_FILE" && "$ROTATE_SECRET" != "1" ]]; then
  SECRET="$(tr -d '\n' < "$MTG_SECRET_FILE")"
else
  if [[ "$MODE" == "faketls" ]]; then
    SECRET="$("$MTG_BINARY" generate-secret --hex "$DOMAIN")"
  else
    SECRET="$("$MTG_BINARY" generate-secret)"
  fi
  echo "$SECRET" > "$MTG_SECRET_FILE"
fi

cat > "$MTG_CONFIG" <<TOML
secret = "${SECRET}"
bind-to = "${HOST_IP}:${MTG_PORT}"
TOML

if [[ "$MODE" == "faketls" && "$LOCAL_TLS_PROXY" == "nginx" && -n "$LOCAL_TLS_PORT" ]]; then
  patch_nginx_for_local_tls "$NGINX_SITE" "$LOCAL_TLS_PORT"
  patch_hosts_for_domain "$DOMAIN"
  nginx -s reload
  write_faketls_state
else
  clear_faketls_state
fi

backup_file "$MTG_SERVICE_FILE"
cat > "$MTG_SERVICE_FILE" <<UNIT
[Unit]
Description=MTProxy (mtg)
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=${MTG_BINARY} run ${MTG_CONFIG}
Restart=on-failure
RestartSec=3

[Install]
WantedBy=multi-user.target
UNIT

systemctl daemon-reload
systemctl enable --now mtg
if command -v ufw >/dev/null 2>&1; then
  ufw allow "$MTG_PORT"/tcp >/dev/null 2>&1 || true
fi

echo
echo "mode: $MODE"
echo "host_ip: $HOST_IP"
echo "port: $MTG_PORT"
if [[ -n "$DOMAIN" ]]; then
  echo "domain: $DOMAIN"
fi
echo "secret_rotated: $ROTATE_SECRET"
echo
echo "mtg_status:"
systemctl --no-pager --full status mtg | sed -n '1,10p'
echo
echo "telegram_link:"
echo "tg://proxy?server=$HOST_IP&port=$MTG_PORT&secret=$SECRET"
echo "https://t.me/proxy?server=$HOST_IP&port=$MTG_PORT&secret=$SECRET"
