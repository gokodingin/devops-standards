# Strategi Shared Database & CI/CD Auto-Registration NPM

Dokumen ini menjelaskan 2 solusi teknis terintegrasi:
1. **GitHub Actions Workflow**: Otomatis mendaftarkan / mengupdate Proxy Host di Nginx Proxy Manager (NPM) via REST API saat deployment.
2. **Strategi Deteksi Shared Database**: Menghilangkan container database ganda di setiap project, mendeteksi keberadaan shared DB di host/Docker network, dan otomatis membuat database baru jika belum ada.

---

## 1. Kondisi Database Shared di Server `100.101.0.48`

Di server saat ini sudah berjalan 2 instance database terpusat yang terhubung ke `shared_network`:

| Engine | Container Name | Internal Port | Status di `shared_network` | Credential Utama |
| :--- | :--- | :--- | :--- | :--- |
| **PostgreSQL 15** | `DB_POSTGRE` | `5432` | Terhubung (`172.26.0.3`) | user: `gokodingin` / db: `postgres` |
| **MariaDB / MySQL 10.11** | `mariadb_server` | `3306` | Terhubung (`172.26.0.20`) | user: `root` |

> **Prinsip Utama:** Setiap project baru **tidak boleh** menyalakan container `postgres` atau `mysql` sendiri di host, karena memboroskan RAM, port host, dan disk I/O. Container aplikasi cukup terhubung ke `shared_network` dan mengarahkan host database ke `DB_POSTGRE:5432` atau `mariadb_server:3306`.

---

## 2. Strategi Deteksi & Auto-Provision Database

Ada 2 cara yang dapat diterapkan:

### Pola A: Docker Compose Profile (`profiles: ["local-db"]`) — *Standar Paling Bersih*
Di file `docker-compose.yml` masing-masing project:
```yaml
version: '3.8'

services:
  app:
    build: .
    container_name: myapp_app
    restart: unless-stopped
    expose:
      - "3000"
    environment:
      # Default mengarah ke shared DB di server
      - DATABASE_URL=${DATABASE_URL:-postgresql://gokodingin:GoKodingin2024@DB_POSTGRE:5432/myapp_db}
    networks:
      - shared_network

  # Service database ini HANYA menyala jika dijalankan di laptop lokal dengan flag:
  # docker compose --profile local-db up -d
  # Di server production, flag ini tidak dipakai sehingga container DB TIDAK dibuat!
  db:
    image: postgres:15-alpine
    profiles:
      - local-db
    environment:
      - POSTGRES_USER=postgres
      - POSTGRES_PASSWORD=postgres
      - POSTGRES_DB=myapp_db
    networks:
      - shared_network

networks:
  shared_network:
    external: true
```

### Pola B: Script Deteksi & Auto-Create Database (Shell/CI)
Sebelum `docker compose up -d`, script mengecek apakah container `DB_POSTGRE` aktif di server. Jika aktif, script otomatis membuat database untuk project tersebut jika belum ada:

```bash
# Cek apakah container DB_POSTGRE ada di server
if docker ps --format '{{.Names}}' | grep -q "^DB_POSTGRE$"; then
  echo "Shared PostgreSQL terdeteksi. Memastikan database myapp_db tersedia..."
  docker exec DB_POSTGRE psql -U gokodingin -d postgres -tc "SELECT 1 FROM pg_database WHERE datname = 'myapp_db'" | grep -q 1 || \
## 3. Script CLI / Helper Idempotent NPM Sync (`sync-npm-proxy`)

Script sinkronisasi NPM telah dipasang secara **global di server target**:
Path di server: `/usr/local/bin/sync-npm-proxy`

### Penggunaan Langsung dari Terminal Server (`100.101.0.48`):
```bash
export NPM_PASSWORD="Password_NPM_Anda"
sync-npm-proxy <DOMAIN> <FORWARD_HOST> [PORT]

# Contoh:
sync-npm-proxy "dashboard-crm.gokodingin.com" "dashboard-crm-app-1" 80
```
Script ini bersifat **idempotent**: jika domain sudah ada di NPM, ia akan mengupdate config-nya; jika belum ada, ia akan membuat Proxy Host baru.

---

## 4. Template GitHub Actions Workflow (`.github/workflows/deploy.yml`)

Workflow ini menggunakan path native server target (`/home/gokodingin/<nama-repo>`):

```yaml
name: Deploy Application

on:
  push:
    branches:
      - main
      - production

jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - name: Checkout Code
        uses: actions/checkout@v4

      - name: Deploy to Server via SSH
        uses: appleboy/ssh-action@v1.0.3
        with:
          host: ${{ secrets.SERVER_HOST }}       # 100.101.0.48 / Tailscale IP / Server Host
          username: ${{ secrets.SERVER_USER }}   # root / user deploy server
          key: ${{ secrets.SSH_PRIVATE_KEY }}
          script: |
            set -e
            # Path project di server target:
            cd /home/gokodingin/${{ github.event.repository.name }}

            # 1. Cek & Siapkan Shared Database
            if docker ps --format '{{.Names}}' | grep -q "^DB_POSTGRE$"; then
              echo "[DB] Menggunakan PostgreSQL shared (DB_POSTGRE)..."
              docker exec DB_POSTGRE psql -U gokodingin -d postgres -tc "SELECT 1 FROM pg_database WHERE datname = 'myapp_prod'" | grep -q 1 || \
              docker exec DB_POSTGRE psql -U gokodingin -d postgres -c "CREATE DATABASE myapp_prod;"
              COMPOSE_PROFILE=""
            else
              echo "[DB] DB_POSTGRE tidak ditemukan, menyalakan local fallback..."
              COMPOSE_PROFILE="--profile local-db"
            fi

            # 2. Deploy Container Aplikasi
            git pull origin main
            docker compose $COMPOSE_PROFILE up -d --build

      - name: Auto Register Subdomain ke Nginx Proxy Manager (NPM)
        uses: appleboy/ssh-action@v1.0.3
        env:
          NPM_PASSWORD: ${{ secrets.NPM_PASSWORD }}
        with:
          host: ${{ secrets.SERVER_HOST }}
          username: ${{ secrets.SERVER_USER }}
          key: ${{ secrets.SSH_PRIVATE_KEY }}
          envs: NPM_PASSWORD
          script: |
            # Memanggil binary global yang sudah terinstall di /usr/local/bin/sync-npm-proxy di server
            sync-npm-proxy \
              "${{ vars.APP_DOMAIN || 'myapp.gokodingin.com' }}" \
              "${{ vars.APP_CONTAINER_NAME || 'myapp_app' }}" \
              ${{ vars.APP_PORT || 80 }}
```

### GitHub Secrets yang Dibutuhkan:
- `SERVER_HOST`: IP server (`100.101.0.48` atau domain SSH Anda).
- `SERVER_USER`: `root`.
- `SSH_PRIVATE_KEY`: Private SSH Key untuk remote server.
- `NPM_PASSWORD`: Password login akun NPM `gokodingin@gmail.com`.
