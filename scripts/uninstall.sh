#!/usr/bin/env bash
set -euo pipefail

MTG_BINARY="/usr/local/bin/mtg"
MTG_CONFIG_DIR="/etc/mtg"
MTG_SERVICE_FILE="/etc/systemd/system/mtg.service"
MTG_PORT=""
FAKETLS_STATE_FILE="$MTG_CONFIG_DIR/faketls.env"

usage() {
  cat <<USAGE
Usage:
  sudo ./scripts/uninstall.sh [--port PORT]

If --port is not given, the port is read from /etc/mtg/config.toml automatically.
USAGE
}

restore_faketls_side_effects() {
  if [[ ! -f "$FAKETLS_STATE_FILE" ]]; then
    return 0
  fi
  # shellcheck disable=SC1090
  . "$FAKETLS_STATE_FILE"
  if [[ "${LOCAL_TLS_PROXY:-}" == "nginx" && -n "${NGINX_SITE:-}" && -f "${NGINX_SITE:-}" ]]; then
    python3 - "$NGINX_SITE" <<'PY'
from pathlib import Path
import sys
site = Path(sys.argv[1])
text = site.read_text()
text = text.replace('    listen 127.0.0.1:443 ssl;\n', '')
site.write_text(text)
PY
    nginx -t && systemctl restart nginx
  fi
  if [[ -n "${DOMAIN:-}" && -f /etc/hosts ]]; then
    python3 - "$DOMAIN" <<'PY'
from pathlib import Path
import sys
p = Path('/etc/hosts')
domain = sys.argv[1]
lines = p.read_text().splitlines()
filtered = [line for line in lines if line.strip() != f'127.0.0.1 {domain}']
p.write_text('\n'.join(filtered) + ('\n' if filtered else ''))
PY
  fi
}

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

restore_faketls_side_effects
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
