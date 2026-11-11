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

### 5. Ambil Template `docker-compose.dev.yml` (Live Mount & Hot-Reload Dev)
```bash
curl -sSL https://raw.githubusercontent.com/gokodingin/devops-standards/main/templates/docker-compose.dev.template.yml -o docker-compose.dev.yml
```
---

## 🚀 Reusable CI/CD Pipeline (Integration Test -> Staging -> Production)

Seluruh project GoKodingin wajib memiliki pipeline CI/CD 3 tahap yang saling bergantung (**dependent pipeline**):

1. **Stage 1: `integration-test` (Gatekeeper)**: Menjalankan test unit/integration, compile/build check, dan validasi sintaks Docker Compose. Jika gagal, deployment otomatis dibatalkan.
2. **Stage 2: `deploy-staging`**: Bergantung (`needs: integration-test`). Hanya aktif di branch `staging`/`develop`. Menerapkan `docker-compose.staging.yml`.
3. **Stage 3: `deploy-production`**: Bergantung (`needs: integration-test`). Hanya aktif di branch `main`/`master`. Menerapkan `docker-compose.yml`.

### Cara Pasang di Project Baru:
```bash
mkdir -p .github/workflows
curl -sSL https://raw.githubusercontent.com/gokodingin/devops-standards/main/templates/pipeline.template.yml -o .github/workflows/pipeline.yml
```

---

## 🛠️ Scripts & Utilities

- `scripts/sync-npm-proxy.sh`: Script sinkronisasi NPM via REST API (juga terinstall global di server di `/usr/local/bin/sync-npm-proxy`).
- `scripts/check-proxy-mesh.sh`: Script diagnostik kesehatan jaringan internal Docker dan resolusi DNS antar container.
