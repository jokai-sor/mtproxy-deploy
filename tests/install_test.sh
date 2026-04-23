#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck disable=SC1091
source "$ROOT_DIR/scripts/install.sh"

systemctl_calls=()

nginx() {
  return 0
}

systemctl() {
  systemctl_calls+=("$*")
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

assert_file_contains() {
  local file="$1"
  local needle="$2"
  local message="$3"
  if ! grep -qF "$needle" "$file"; then
    echo "FAIL: $message" >&2
    echo "  missing: $needle" >&2
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

assert_success() {
  local message="$1"
  shift
  if ! "$@"; then
    echo "FAIL: $message" >&2
    exit 1
  fi
}

assert_failure() {
  local message="$1"
  shift
  if "$@"; then
    echo "FAIL: $message" >&2
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

standard_secret="0123456789abcdef0123456789abcdef"
same_domain_secret="$(make_faketls_secret "00112233445566778899aabbccddeeff" "jks.vps.webdock.cloud")"
other_domain_secret="$(make_faketls_secret "00112233445566778899aabbccddeeff" "old.example.com")"

MODE="faketls"
DOMAIN="jks.vps.webdock.cloud"
assert_success "extract_faketls_domain should decode domain" extract_faketls_domain "$same_domain_secret" >/dev/null
assert_eq "jks.vps.webdock.cloud" "$(extract_faketls_domain "$same_domain_secret")" "decoded FakeTLS domain should match"
assert_failure "same faketls domain should keep secret" secret_requires_rotation "$same_domain_secret"

MODE="faketls"
DOMAIN="new.example.com"
assert_success "different faketls domain should rotate secret" secret_requires_rotation "$same_domain_secret"

MODE="standard"
DOMAIN=""
assert_success "switching from faketls to standard should rotate secret" secret_requires_rotation "$same_domain_secret"
assert_failure "standard secret in standard mode should be preserved" secret_requires_rotation "$standard_secret"

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

MODE="standard"
DOMAIN=""
reconcile_faketls_side_effects "$other_domain_secret"

assert_file_not_contains "$NGINX_SITE" "listen 127.0.0.1:443 ssl;" "legacy nginx listener should be removed without state file"
assert_file_not_contains "$HOSTS_FILE" "127.0.0.1 old.example.com" "legacy hosts entry should be removed without state file"

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

MODE="faketls"
DOMAIN="current.example.com"
LOCAL_TLS_PROXY="nginx"
LOCAL_TLS_PORT="4443"
restore_faketls_side_effects

assert_file_not_contains "$NGINX_SITE" "listen 127.0.0.1:443 ssl;" "state-based restore should remove nginx listener"
assert_file_not_contains "$HOSTS_FILE" "127.0.0.1 state.example.com" "state-based restore should remove hosts entry"
assert_eq "missing" "$(test -f "$FAKETLS_STATE_FILE" && echo present || echo missing)" "state file should be removed after restore"
assert_eq "current.example.com" "$DOMAIN" "state restore should not clobber current install domain"

systemctl_calls=()
apply_mtg_service
assert_eq "daemon-reload enable mtg restart mtg" "${systemctl_calls[*]}" "install lifecycle should restart mtg after writing binary/config/unit"

echo "install_test.sh: ok"
