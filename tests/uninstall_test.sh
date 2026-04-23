#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck disable=SC1091
source "$ROOT_DIR/scripts/uninstall.sh"

nginx() {
  return 0
}

systemctl() {
  return 0
}

assert_eq() {
  local expected="$1"
  local actual="$2"
  local message="$3"
  if [[ "$expected" != "$actual" ]]; then
    echo "FAIL: $message" >&2
    echo "  expected: $expected" >&2
    echo "  actual:   $actual" >&2
    exit 1
  fi
}

assert_file_not_contains() {
  local file="$1"
  local needle="$2"
  local message="$3"
  if grep -qF "$needle" "$file"; then
    echo "FAIL: $message" >&2
    echo "  unexpected: $needle" >&2
    exit 1
  fi
}

make_faketls_secret() {
  local prefix="$1"
  local domain="$2"
  python3 - "$prefix" "$domain" <<'PY'
import sys
prefix, domain = sys.argv[1], sys.argv[2]
print("ee" + prefix + domain.encode().hex())
PY
}

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

STAMP="test"
HOSTS_FILE="$tmpdir/hosts"
NGINX_SITE="$tmpdir/webdock"
FAKETLS_STATE_FILE="$tmpdir/faketls.env"

legacy_secret="$(make_faketls_secret "00112233445566778899aabbccddeeff" "old.example.com")"

cat > "$NGINX_SITE" <<'EOF'
server {
    listen 4443 ssl; # managed by Certbot
    listen 127.0.0.1:443 ssl;
}
EOF

cat > "$HOSTS_FILE" <<'EOF'
127.0.0.1 localhost
127.0.0.1 old.example.com
EOF

reconcile_faketls_side_effects "$legacy_secret"

assert_file_not_contains "$NGINX_SITE" "listen 127.0.0.1:443 ssl;" "uninstall should remove legacy nginx listener without state file"
assert_file_not_contains "$HOSTS_FILE" "127.0.0.1 old.example.com" "uninstall should remove legacy hosts entry without state file"

cat > "$NGINX_SITE" <<'EOF'
server {
    listen 4443 ssl; # managed by Certbot
    listen 127.0.0.1:443 ssl;
}
EOF

cat > "$HOSTS_FILE" <<'EOF'
127.0.0.1 localhost
127.0.0.1 state.example.com
EOF

cat > "$FAKETLS_STATE_FILE" <<EOF
MODE=faketls
DOMAIN=state.example.com
LOCAL_TLS_PROXY=nginx
LOCAL_TLS_PORT=4443
NGINX_SITE=$NGINX_SITE
EOF

reconcile_faketls_side_effects ""

assert_file_not_contains "$NGINX_SITE" "listen 127.0.0.1:443 ssl;" "uninstall should remove state-based nginx listener"
assert_file_not_contains "$HOSTS_FILE" "127.0.0.1 state.example.com" "uninstall should remove state-based hosts entry"
assert_eq "missing" "$(test -f "$FAKETLS_STATE_FILE" && echo present || echo missing)" "state file should be removed after uninstall cleanup"

echo "uninstall_test.sh: ok"
