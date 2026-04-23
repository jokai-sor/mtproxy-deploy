#!/usr/bin/env bash
set -euo pipefail

MTG_BINARY="/usr/local/bin/mtg"
MTG_CONFIG_DIR="/etc/mtg"
MTG_SERVICE_FILE="/etc/systemd/system/mtg.service"
MTG_PORT=""
FAKETLS_STATE_FILE="$MTG_CONFIG_DIR/faketls.env"
HOSTS_FILE="/etc/hosts"
NGINX_SITE="/etc/nginx/sites-enabled/webdock"
STAMP="$(date +%F-%H%M%S)"

usage() {
  cat <<USAGE
Usage:
  sudo ./scripts/uninstall.sh [--port PORT]

If --port is not given, the port is read from /etc/mtg/config.toml automatically.
USAGE
}

restore_faketls_side_effects() {
  if [[ ! -f "$FAKETLS_STATE_FILE" ]]; then
    return 1
  fi
  local state_domain state_local_tls_proxy state_nginx_site nginx_changed=0
  local current_nginx_site
  current_nginx_site="$NGINX_SITE"
  state_domain=""
  state_local_tls_proxy=""
  state_nginx_site=""
  # shellcheck disable=SC1090
  . "$FAKETLS_STATE_FILE"
  state_domain="${DOMAIN:-}"
  state_local_tls_proxy="${LOCAL_TLS_PROXY:-}"
  state_nginx_site="${NGINX_SITE:-}"
  NGINX_SITE="$current_nginx_site"
  if [[ "$state_local_tls_proxy" == "nginx" ]] && remove_nginx_local_tls_listener "$state_nginx_site"; then
    nginx_changed=1
  fi
  remove_hosts_domain_entry "$state_domain" || true
  if (( nginx_changed )); then
    nginx -t && systemctl restart nginx
  fi
  rm -f "$FAKETLS_STATE_FILE"
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
  rm -f "$FAKETLS_STATE_FILE"
}

main() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --port) MTG_PORT="$2"; shift 2 ;;
      -h|--help) usage; exit 0 ;;
      *) echo "unknown argument: $1" >&2; usage; exit 1 ;;
    esac
  done

  if [[ "${EUID}" -ne 0 ]]; then
    echo "run as root: sudo ./scripts/uninstall.sh" >&2
    exit 1
  fi

  if [[ -z "$MTG_PORT" ]]; then
    cfg_port="$(sed -n 's/^bind-to *= *"[^:]*:\([0-9]*\)".*/\1/p' \
      "$MTG_CONFIG_DIR/config.toml" 2>/dev/null | head -1 || true)"
    if [[ -n "$cfg_port" ]]; then
      MTG_PORT="$cfg_port"
      echo "port: read from config ($MTG_PORT)"
    else
      MTG_PORT="8443"
      echo "port: config not found, using default ($MTG_PORT)"
    fi
  fi

  existing_secret=""
  if [[ -f "$MTG_CONFIG_DIR/secret" ]]; then
    existing_secret="$(tr -d '\n' < "$MTG_CONFIG_DIR/secret")"
  fi

  reconcile_faketls_side_effects "$existing_secret"
  systemctl disable --now mtg >/dev/null 2>&1 || true
  rm -f "$MTG_SERVICE_FILE"
  systemctl daemon-reload
  if command -v ufw >/dev/null 2>&1; then
    ufw delete allow "$MTG_PORT"/tcp >/dev/null 2>&1 || true
  fi
  rm -f "$MTG_BINARY"
  rm -rf "$MTG_CONFIG_DIR"

  echo "removed:"
  echo "  $MTG_SERVICE_FILE"
  echo "  $MTG_CONFIG_DIR"
  echo "  $MTG_BINARY"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  main "$@"
fi
