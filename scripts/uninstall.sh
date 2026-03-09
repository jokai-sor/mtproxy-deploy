#!/usr/bin/env bash
set -euo pipefail

MTPROXY_DIR="/opt/MTProxy"
MTPROXY_SECRET_FILE="/etc/mtproxy/secret"
MTPROXY_SERVICE_FILE="/etc/systemd/system/mtproxy.service"
MTPROXY_PORT="8443"

usage() {
  cat <<USAGE
Usage:
  sudo ./scripts/uninstall.sh [--port PORT]
USAGE
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
