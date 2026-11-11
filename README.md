# GoKodingin DevOps & Infrastructure Standards

Repository terpusat untuk standar arsitektur infrastruktur, routing, template multi-stage container Docker, dan reusable CI/CD workflows untuk server `100.101.0.48`.

---

## 📚 Daftar Panduan Utama

1. **[Strategi Routing Wildcard Cloudflare Tunnel & NPM](docs/INFRA_ROUTING_STRATEGY.md)**  
   Topologi jaringan internal `shared_network`, dual tunnel (`home-server` & `orange-server`), pencegahan redirect loop, dan zero-host-port exposure.
2. **[Multi-Stage Dockerfile Guide](docs/MULTI_STAGE_DOCKER_GUIDE.md)**  
   Standar multi-stage build untuk Node.js/TypeScript dan Frontend SPA untuk memisahkan stage Dev, Staging, dan Production (merampingkan size container >70%).
3. **[Shared Database & CI/CD Strategy](docs/SHARED_DB_AND_CI_CD_STRATEGY.md)**  
   Mencegah pembuatan container database berulang di setiap project, auto-provision DB di `DB_POSTGRE` & `mariadb_server`, serta auto-registrasi subdomain via REST API NPM.

---

## ⚡ Quick Start: Ambil Template Langsung ke Project Baru

Cukup jalankan perintah cURL berikut di dalam folder project baru Anda:

### 1. Ambil Template Multi-Stage Dockerfile (Node.js/TypeScript Backend)
```bash
curl -sSL https://raw.githubusercontent.com/gokodingin/devops-standards/main/templates/Dockerfile.node -o Dockerfile
```

### 2. Ambil Template Multi-Stage Dockerfile (Frontend SPA Vite/React/Vue)
```bash
curl -sSL https://raw.githubusercontent.com/gokodingin/devops-standards/main/templates/Dockerfile.spa -o Dockerfile
```

### 3. Ambil Template `docker-compose.yml` (Zero-Host-Port & Shared DB)
```bash
curl -sSL https://raw.githubusercontent.com/gokodingin/devops-standards/main/templates/docker-compose.template.yml -o docker-compose.yml
```

### 4. Ambil Template `.dockerignore` Standar
```bash
curl -sSL https://raw.githubusercontent.com/gokodingin/devops-standards/main/templates/dockerignore.template -o .dockerignore
```

### 5. Ambil Template `docker-compose.override.yml` (Live Mount & Hot-Reload Dev)
```bash
curl -sSL https://raw.githubusercontent.com/gokodingin/devops-standards/main/templates/docker-compose.override.yml.example -o docker-compose.override.yml
```

---

## 🚀 Reusable GitHub Actions Workflow (CI/CD 5 Baris)

Di repository project apa pun di akun `gokodingin`, Anda **tidak perlu lagi menulis script SSH yang panjang**. Cukup panggil reusable workflow dari repo ini:

Buat file `.github/workflows/deploy.yml` di project Anda:

```yaml
name: Deploy to Production

on:
  push:
    branches:
      - main
      - production

jobs:
  deploy:
    uses: gokodingin/devops-standards/.github/workflows/reusable-deploy.yml@main
    secrets: inherit
    with:
      domain: "myapp.gokodingin.com"      # Subdomain publik yang diinginkan
      container_name: "myapp_app"         # Nama container di compose
      port: 3000                          # Port internal container
      db_type: "postgres"                 # postgres | mariadb | none
      db_name: "myapp_prod"               # Otomatis dibuat jika belum ada di shared DB
```

---

## 🛠️ Scripts & Utilities

- `scripts/sync-npm-proxy.sh`: Script sinkronisasi NPM via REST API (juga terinstall global di server di `/usr/local/bin/sync-npm-proxy`).
- `scripts/check-proxy-mesh.sh`: Script diagnostik kesehatan jaringan internal Docker dan resolusi DNS antar container.
