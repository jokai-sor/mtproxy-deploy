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
HOSTS_FILE="/etc/hosts"
ROTATE_SECRET="0"
DEFAULT_MTG_VERSION="2.2.8"
MTG_VERSION="$DEFAULT_MTG_VERSION"

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
  --mtg-version VERSION     install this exact version (default: ${DEFAULT_MTG_VERSION})
USAGE
}

validate_ip() {
  local ip="$1"
  local re='^(([0-9]|[1-9][0-9]|1[0-9]{2}|2[0-4][0-9]|25[0-5])\.){3}([0-9]|[1-9][0-9]|1[0-9]{2}|2[0-4][0-9]|25[0-5])$'
  [[ "$ip" =~ $re ]]
}

validate_port() {
  [[ "$1" =~ ^[0-9]+$ ]] && (( $1 >= 1 && $1 <= 65535 ))
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
  backup_file "$HOSTS_FILE"
  if ! grep -qE "^[[:space:]]*127\.0\.0\.1[[:space:]].*\b${domain//./\.}\b" "$HOSTS_FILE"; then
    printf '127.0.0.1 %s\n' "$domain" >> "$HOSTS_FILE"
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

is_faketls_secret() {
  local secret="$1"
  [[ "$secret" =~ ^ee[0-9a-f]+$ ]] && (( ${#secret} > 34 ))
}

extract_faketls_domain() {
  local secret="$1"
  is_faketls_secret "$secret" || return 1
  python3 - "$secret" <<'PY'
import sys

secret = sys.argv[1]
hex_domain = secret[34:]
try:
    print(bytes.fromhex(hex_domain).decode())
except Exception as exc:
    raise SystemExit(f"invalid faketls secret domain: {exc}")
PY
}

remove_nginx_local_tls_listener() {
  local site="$1"
  [[ -f "$site" ]] || return 1
  grep -qF 'listen 127.0.0.1:443 ssl;' "$site" || return 1
  backup_file "$site"
  python3 - "$site" <<'PY'
from pathlib import Path
import sys
site = Path(sys.argv[1])
text = site.read_text()
text = text.replace('    listen 127.0.0.1:443 ssl;\n', '')
site.write_text(text)
PY
}

remove_hosts_domain_entry() {
  local domain="$1"
  [[ -n "$domain" && -f "$HOSTS_FILE" ]] || return 1
  grep -qE "^[[:space:]]*127\.0\.0\.1[[:space:]].*\b${domain//./\.}\b" "$HOSTS_FILE" || return 1
  backup_file "$HOSTS_FILE"
  python3 - "$HOSTS_FILE" "$domain" <<'PY'
from pathlib import Path
import sys
p = Path(sys.argv[1])
domain = sys.argv[2]
lines = p.read_text().splitlines()
filtered = [line for line in lines if line.strip() != f'127.0.0.1 {domain}']
p.write_text('\n'.join(filtered) + ('\n' if filtered else ''))
PY
}

restore_faketls_side_effects() {
  if [[ ! -f "$FAKETLS_STATE_FILE" ]]; then
    return 1
  fi
  local state_domain state_local_tls_proxy state_nginx_site nginx_changed=0
  local current_domain current_local_tls_proxy current_local_tls_port current_nginx_site
  current_domain="$DOMAIN"
  current_local_tls_proxy="$LOCAL_TLS_PROXY"
  current_local_tls_port="$LOCAL_TLS_PORT"
  current_nginx_site="$NGINX_SITE"
  state_domain=""
  state_local_tls_proxy=""
  state_nginx_site=""
  # shellcheck disable=SC1090
  . "$FAKETLS_STATE_FILE"
  state_domain="${DOMAIN:-}"
  state_local_tls_proxy="${LOCAL_TLS_PROXY:-}"
  state_nginx_site="${NGINX_SITE:-}"
  DOMAIN="$current_domain"
  LOCAL_TLS_PROXY="$current_local_tls_proxy"
  LOCAL_TLS_PORT="$current_local_tls_port"
  NGINX_SITE="$current_nginx_site"
  if [[ "$state_local_tls_proxy" == "nginx" ]] && remove_nginx_local_tls_listener "$state_nginx_site"; then
    nginx_changed=1
  fi
  remove_hosts_domain_entry "$state_domain" || true
  if (( nginx_changed )); then
    nginx -t && systemctl restart nginx
  fi
  clear_faketls_state
}

secret_requires_rotation() {
  local existing_secret="$1"

  if [[ "$MODE" == "faketls" ]]; then
    local existing_domain
    if ! is_faketls_secret "$existing_secret"; then
      return 0
    fi
    existing_domain="$(extract_faketls_domain "$existing_secret")" || return 0
    [[ "$existing_domain" != "$DOMAIN" ]]
    return $?
  fi

  [[ "$existing_secret" == ee* ]]
}

reconcile_faketls_side_effects() {
  local existing_secret="${1:-}"
  local legacy_domain="" nginx_changed=0

  if restore_faketls_side_effects; then
    return 0
  fi

  if is_faketls_secret "$existing_secret"; then
    legacy_domain="$(extract_faketls_domain "$existing_secret" 2>/dev/null || true)"
  fi

  if remove_nginx_local_tls_listener "$NGINX_SITE"; then
    nginx_changed=1
  fi
  if [[ -n "$legacy_domain" ]]; then
    remove_hosts_domain_entry "$legacy_domain" || true
  fi
  if (( nginx_changed )); then
    nginx -t && systemctl restart nginx
  fi
  clear_faketls_state
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

  local version="$MTG_VERSION"

  echo "installing mtg v${version} (${arch})..."
  local url="https://github.com/9seconds/mtg/releases/download/v${version}/mtg-${version}-linux-${arch}.tar.gz"
  local tmpdir
  tmpdir="$(mktemp -d)"
  trap 'if [[ -n "${tmpdir:-}" ]]; then rm -rf "$tmpdir"; fi' RETURN
  curl -fsSL "$url" | tar xz -C "$tmpdir"
  install -m 0755 "$tmpdir"/*/mtg "$MTG_BINARY"
}

apply_mtg_service() {
  systemctl daemon-reload
  systemctl enable mtg
  systemctl restart mtg
}

main() {
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
      --mtg-version) MTG_VERSION="$2"; shift 2 ;;
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

  validate_ip "$HOST_IP" || { echo "invalid host IP: $HOST_IP" >&2; exit 1; }
  validate_port "$MTG_PORT" || { echo "invalid port: $MTG_PORT (must be 1-65535)" >&2; exit 1; }

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
  LINK_SERVER="$HOST_IP"

  if [[ -n "$DOMAIN" ]]; then
    LINK_SERVER="$DOMAIN"
  fi

  apt-get update -q
  apt-get install -y -q curl xxd ufw

  install_mtg
  ensure_config_dir

  PREVIOUS_SECRET=""
  if [[ ! -f "$MTG_SECRET_FILE" ]]; then
    ROTATE_SECRET="1"
  fi

  if [[ -f "$MTG_SECRET_FILE" && "$ROTATE_SECRET" != "1" ]]; then
    SECRET="$(tr -d '\n' < "$MTG_SECRET_FILE")"
    PREVIOUS_SECRET="$SECRET"
    if secret_requires_rotation "$SECRET"; then
      ROTATE_SECRET="1"
    fi
  elif [[ -f "$MTG_SECRET_FILE" ]]; then
    PREVIOUS_SECRET="$(tr -d '\n' < "$MTG_SECRET_FILE")"
  fi

  if [[ "$ROTATE_SECRET" == "1" ]]; then
    if [[ "$MODE" == "faketls" ]]; then
      SECRET="$("$MTG_BINARY" generate-secret --hex "$DOMAIN")"
    else
      SECRET="$("$MTG_BINARY" generate-secret)"
    fi
    echo "$SECRET" > "$MTG_SECRET_FILE"
  else
    : "${SECRET:?failed to read existing secret}"
  fi

  cat > "$MTG_CONFIG" <<TOML
secret = "${SECRET}"
bind-to = "${HOST_IP}:${MTG_PORT}"
TOML

  reconcile_faketls_side_effects "$PREVIOUS_SECRET"

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

  apply_mtg_service
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
  echo "tg://proxy?server=$LINK_SERVER&port=$MTG_PORT&secret=$SECRET"
  echo "https://t.me/proxy?server=$LINK_SERVER&port=$MTG_PORT&secret=$SECRET"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  main "$@"
fi
