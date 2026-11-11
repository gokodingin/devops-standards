#!/usr/bin/env bash
# scripts/sync-npm-proxy.sh
# Script idempotent untuk mendaftarkan / memperbarui Proxy Host di Nginx Proxy Manager via REST API.

set -euo pipefail

NPM_HOST="${NPM_HOST:-http://100.101.0.48:81}"
NPM_EMAIL="${NPM_EMAIL:-gokodingin@gmail.com}"
NPM_PASSWORD="${NPM_PASSWORD:-}"

DOMAIN="${1:-}"
FORWARD_HOST="${2:-}"
FORWARD_PORT="${3:-80}"

if [ -z "$DOMAIN" ] || [ -z "$FORWARD_HOST" ]; then
    echo "Usage: $0 <DOMAIN> <FORWARD_HOST> [FORWARD_PORT]"
    echo "Example: $0 myapp.gokodingin.com myapp-container 3000"
    exit 1
fi

if [ -z "$NPM_PASSWORD" ]; then
    echo "Error: Environment variable NPM_PASSWORD is required."
    exit 1
fi

echo "[1/3] Login ke NPM API ($NPM_HOST)..."
LOGIN_PAYLOAD=$(cat <<EOF
{
  "identity": "$NPM_EMAIL",
  "secret": "$NPM_PASSWORD"
}
EOF
)

TOKEN=$(curl -s -f -X POST "$NPM_HOST/api/tokens" \
  -H "Content-Type: application/json" \
  -d "$LOGIN_PAYLOAD" | grep -o '"token":"[^"]*' | cut -d'"' -f4)

if [ -z "$TOKEN" ]; then
    echo "Error: Gagal login ke NPM API. Periksa NPM_EMAIL dan NPM_PASSWORD."
    exit 1
fi
echo "  [OK] Berhasil autentikasi."

echo "[2/3] Memeriksa apakah domain $DOMAIN sudah ada di NPM..."
ALL_HOSTS=$(curl -s -f -X GET "$NPM_HOST/api/nginx/proxy-hosts" \
  -H "Authorization: Bearer $TOKEN")

EXISTING_ID=$(node -e '
const hosts = JSON.parse(process.argv[1]);
const targetDomain = process.argv[2];
const found = hosts.find(h => Array.isArray(h.domain_names) && h.domain_names.includes(targetDomain));
console.log(found ? found.id : "");
' "$ALL_HOSTS" "$DOMAIN")

PROXY_PAYLOAD=$(cat <<EOF
{
  "domain_names": ["$DOMAIN"],
  "forward_scheme": "http",
  "forward_host": "$FORWARD_HOST",
  "forward_port": $FORWARD_PORT,
  "caching_enabled": false,
  "block_exploits": true,
  "allow_websocket_upgrade": true,
  "access_list_id": 0,
  "certificate_id": 0,
  "ssl_forced": false,
  "http2_support": false,
  "hsts_enabled": false,
  "hsts_subdomains": false,
  "advanced_config": "",
  "meta": {}
}
EOF
)

if [ -n "$EXISTING_ID" ]; then
    echo "[3/3] Domain $DOMAIN ditemukan (ID: $EXISTING_ID). Memperbarui Proxy Host..."
    curl -s -f -X PUT "$NPM_HOST/api/nginx/proxy-hosts/$EXISTING_ID" \
      -H "Authorization: Bearer $TOKEN" \
      -H "Content-Type: application/json" \
      -d "$PROXY_PAYLOAD" > /dev/null
    echo "  [OK] Proxy Host $DOMAIN berhasil diperbarui -> $FORWARD_HOST:$FORWARD_PORT"
else
    echo "[3/3] Domain $DOMAIN belum ada. Membuat Proxy Host baru..."
    curl -s -f -X POST "$NPM_HOST/api/nginx/proxy-hosts" \
      -H "Authorization: Bearer $TOKEN" \
      -H "Content-Type: application/json" \
      -d "$PROXY_PAYLOAD" > /dev/null
    echo "  [OK] Proxy Host $DOMAIN berhasil dibuat -> $FORWARD_HOST:$FORWARD_PORT"
fi

echo "Selesai! Subdomain https://$DOMAIN siap diakses."
