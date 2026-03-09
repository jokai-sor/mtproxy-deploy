#!/usr/bin/env bash
set -euo pipefail

MTPROXY_DIR="/opt/MTProxy"
MTPROXY_SECRET_FILE="/etc/mtproxy/secret"
MTPROXY_SERVICE_FILE="/etc/systemd/system/mtproxy.service"
MTPROXY_PORT="8443"
FAKETLS_STATE_FILE="/etc/mtproxy/faketls.env"

usage() {
  cat <<USAGE
Usage:
  sudo ./scripts/uninstall.sh [--port PORT]
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
  rm -f "$FAKETLS_STATE_FILE"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --port) MTPROXY_PORT="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "unknown argument: $1" >&2; usage; exit 1 ;;
  esac
done

if [[ "${EUID}" -ne 0 ]]; then
  echo "run as root: sudo ./scripts/uninstall.sh" >&2
  exit 1
fi

restore_faketls_side_effects
systemctl disable --now mtproxy >/dev/null 2>&1 || true
rm -f "$MTPROXY_SERVICE_FILE"
systemctl daemon-reload
if command -v ufw >/dev/null 2>&1; then
  ufw delete allow "$MTPROXY_PORT"/tcp >/dev/null 2>&1 || true
fi
rm -rf "$MTPROXY_DIR"
rm -f "$MTPROXY_SECRET_FILE"

echo "removed:"
echo "  $MTPROXY_SERVICE_FILE"
echo "  $MTPROXY_SECRET_FILE"
echo "  $MTPROXY_DIR"
