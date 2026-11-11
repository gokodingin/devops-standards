#!/usr/bin/env bash
# scripts/check-proxy-mesh.sh
# Verifikasi integritas jaringan dan layer-7 routing antara cloudflared, NPM, dan container aplikasi

set -euo pipefail

echo "=========================================================="
echo " [1/3] Memeriksa koneksi Docker Network (shared_network)"
echo "=========================================================="

CHECK_CONTAINERS=("nginx-proxy-manager-app-1" "cloudflared-tunnel" "home_storage_nginx" "home_storage_nginx_staging")

for c in "${CHECK_CONTAINERS[@]}"; do
    if docker network inspect shared_network --format '{{range .Containers}}{{.Name}} {{end}}' | grep -q "$c"; then
        echo "  [OK] Container $c terhubung ke shared_network"
    else
        echo "  [FAIL] Container $c BELUM terhubung ke shared_network"
    fi
done

echo ""
echo "=========================================================="
echo " [2/3] Memeriksa resolusi DNS internal dari NPM"
echo "=========================================================="

RESOLVE_TARGETS=("home_storage_nginx" "home_storage_nginx_staging" "dashboard-crm-app-1" "print-prod-app-1" "lp-gokodingin-prod")

for target in "${RESOLVE_TARGETS[@]}"; do
    if docker exec nginx-proxy-manager-app-1 getent hosts "$target" > /dev/null 2>&1; then
        IP=$(docker exec nginx-proxy-manager-app-1 getent hosts "$target" | awk '{print $1}')
        echo "  [OK] Resolusi $target -> $IP"
    else
        echo "  [FAIL] Gagal meresolusi $target dari NPM"
    fi
done

echo ""
echo "=========================================================="
echo " [3/3] Memeriksa HTTP Layer-7 Reverse Proxy ke home-storage"
echo "=========================================================="

STATUS_NPM=$(docker exec nginx-proxy-manager-app-1 curl -s -o /dev/null -w "%{http_code}" -H "Host: storage.gokodingin.com" http://127.0.0.1:80/ || true)
if [ "$STATUS_NPM" = "200" ]; then
    echo "  [OK] NPM -> home_storage_nginx (Host: storage.gokodingin.com) mengembalikan HTTP 200 OK"
else
    echo "  [WARN] NPM mengembalikan HTTP $STATUS_NPM (bukan 200)"
fi

STATUS_HEALTH=$(docker exec nginx-proxy-manager-app-1 curl -s -o /dev/null -w "%{http_code}" -H "Host: storage.gokodingin.com" http://127.0.0.1:80/health || true)
if [ "$STATUS_HEALTH" = "200" ]; then
    echo "  [OK] NPM -> home_storage_nginx /health mengembalikan HTTP 200 OK"
else
    echo "  [WARN] Health check mengembalikan HTTP $STATUS_HEALTH"
fi

echo ""
echo "Pemeriksaan selesai."
