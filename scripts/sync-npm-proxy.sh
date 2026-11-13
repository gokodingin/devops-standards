#!/usr/bin/env bash
# scripts/sync-npm-proxy.sh
# Hardened idempotent script to register/update Proxy Hosts in Nginx Proxy Manager via REST API.
# Built with jq (injection-proof), creds via stdin/header, input validation.

set -euo pipefail
umask 077

: "${NPM_HOST:?NPM_HOST environment variable is required (e.g. http://100.101.0.48:81)}"
: "${NPM_EMAIL:?NPM_EMAIL environment variable is required}"
: "${NPM_PASSWORD:?NPM_PASSWORD environment variable is required}"

DOMAIN="${1:-}"
FORWARD_HOST="${2:-}"
FORWARD_PORT="${3:-80}"

if [[ -z "$DOMAIN" || -z "$FORWARD_HOST" ]]; then
    echo "Usage: $0 <DOMAIN> <FORWARD_HOST> [FORWARD_PORT]"
    echo "Example: $0 myapp.gokodingin.com myapp-container 3000"
    exit 2
fi

# 1. Strict regex validations
if ! [[ "$DOMAIN" =~ ^([a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?\.)+[a-z]{2,}$ ]]; then
    echo "Error: Invalid domain format: $DOMAIN" >&2
    exit 2
fi

if ! [[ "$FORWARD_HOST" =~ ^[A-Za-z0-9][A-Za-z0-9_.-]{0,127}$ ]]; then
    echo "Error: Invalid forward host format: $FORWARD_HOST" >&2
    exit 2
fi

if ! [[ "$FORWARD_PORT" =~ ^[0-9]{1,5}$ ]] || (( FORWARD_PORT < 1 || FORWARD_PORT > 65535 )); then
    echo "Error: Invalid forward port: $FORWARD_PORT (must be 1-65535)" >&2
    exit 2
fi

if [[ -n "${ALLOWED_SUFFIXES:-}" ]]; then
    matched=0
    for s in $ALLOWED_SUFFIXES; do
        if [[ "$DOMAIN" == *"$s" ]]; then
            matched=1
            break
        fi
    done
    if (( matched == 0 )); then
        echo "Error: Domain $DOMAIN is outside allowed suffixes ($ALLOWED_SUFFIXES)" >&2
        exit 2
    fi
fi

curl_npm() {
    curl --silent --show-error --fail --max-time 20 --retry 2 "$@"
}

echo "[1/3] Login ke NPM API ($NPM_HOST)..."
LOGIN_PAYLOAD=$(jq -n --arg i "$NPM_EMAIL" --arg s "$NPM_PASSWORD" '{identity: $i, secret: $s}')
TOKEN=$(echo "$LOGIN_PAYLOAD" | curl_npm -X POST "$NPM_HOST/api/tokens" \
    -H "Content-Type: application/json" \
    --data @- | jq -er .token)

if [[ -z "$TOKEN" ]]; then
    echo "Error: Gagal login ke NPM API." >&2
    exit 1
fi
echo "  [OK] Berhasil autentikasi."

HDR=$(mktemp)
trap 'rm -f "$HDR"' EXIT
printf 'Authorization: Bearer %s\n' "$TOKEN" > "$HDR"
unset TOKEN LOGIN_PAYLOAD

api() {
    curl_npm -H @"$HDR" -H "Content-Type: application/json" "$@"
}

echo "[2/3] Memeriksa apakah domain $DOMAIN sudah ada di NPM..."
ALL_HOSTS=$(api "$NPM_HOST/api/nginx/proxy-hosts")
EXISTING_ID=$(echo "$ALL_HOSTS" | jq -r --arg d "$DOMAIN" '[.[] | select(.domain_names | index($d))][0].id // empty')

PROXY_PAYLOAD=$(jq -n \
  --arg d "$DOMAIN" \
  --arg h "$FORWARD_HOST" \
  --argjson p "$FORWARD_PORT" \
  '{
    domain_names: [$d],
    forward_scheme: "http",
    forward_host: $h,
    forward_port: $p,
    caching_enabled: false,
    block_exploits: true,
    allow_websocket_upgrade: true,
    access_list_id: 0,
    certificate_id: 0,
    ssl_forced: false,
    http2_support: false,
    hsts_enabled: false,
    hsts_subdomains: false,
    advanced_config: "",
    meta: {}
  }')

if [[ -n "$EXISTING_ID" ]]; then
    echo "[3/3] Domain $DOMAIN ditemukan (ID: $EXISTING_ID). Memperbarui Proxy Host..."
    echo "$PROXY_PAYLOAD" | api -X PUT "$NPM_HOST/api/nginx/proxy-hosts/$EXISTING_ID" --data @- > /dev/null
    echo "  [OK] Proxy Host $DOMAIN berhasil diperbarui -> $FORWARD_HOST:$FORWARD_PORT"
else
    echo "[3/3] Domain $DOMAIN belum ada. Membuat Proxy Host baru..."
    echo "$PROXY_PAYLOAD" | api -X POST "$NPM_HOST/api/nginx/proxy-hosts" --data @- > /dev/null
    echo "  [OK] Proxy Host $DOMAIN berhasil dibuat -> $FORWARD_HOST:$FORWARD_PORT"
fi

echo "Selesai! Subdomain https://$DOMAIN siap diakses."
