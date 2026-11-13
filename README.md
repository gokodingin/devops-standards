# GoKodingin DevOps & Infrastructure Standards

Repository terpusat untuk standar arsitektur infrastruktur, routing, template multi-stage container Docker, otomasi secret management, dan reusable CI/CD workflows untuk server `100.101.0.48`.

---

## 📚 Daftar Panduan Utama

1. **[Strategi Routing Wildcard Cloudflare Tunnel & NPM](docs/INFRA_ROUTING_STRATEGY.md)**  
   Topologi jaringan internal `shared_network`, dual tunnel (`home-server` & `orange-server`), pencegahan redirect loop, dan zero-host-port exposure.
2. **[Multi-Stage Dockerfile Guide](docs/MULTI_STAGE_DOCKER_GUIDE.md)**  
   Standar multi-stage build untuk Node.js/TypeScript dan Frontend SPA untuk memisahkan stage Dev, Staging, dan Production (merampingkan size container >70%).
3. **[Shared Database & CI/CD Strategy](docs/SHARED_DB_AND_CI_CD_STRATEGY.md)**  
   Mencegah pembuatan container database berulang di setiap project, auto-provision DB di `DB_POSTGRE` & `mariadb_server`, serta auto-registrasi subdomain via REST API NPM.
4. **[Manajemen Secrets & Keamanan CI/CD](docs/SECRET_MANAGEMENT_AND_SECURITY.md)**  
   Prinsip *fail-closed zero-fallback secrets*, otomasi dotenv ke GitHub Environments via `push-secrets.sh`, isolasi SSH forced-command (`gk-deploy.sh`), dan SOP emergency response.

---

## ⚡ Quick Start: Ambil Template Langsung ke Project Baru

Jalankan perintah cURL berikut di dalam folder project baru Anda:

### 1. Ambil Template Multi-Stage Dockerfile (Node.js/TypeScript Backend)
```bash
curl -sSL https://raw.githubusercontent.com/gokodingin/devops-standards/main/templates/Dockerfile.node -o Dockerfile
```

### 2. Ambil Template Multi-Stage Dockerfile (Frontend SPA Vite/React/Vue)
```bash
curl -sSL https://raw.githubusercontent.com/gokodingin/devops-standards/main/templates/Dockerfile.spa -o Dockerfile
```

### 3. Ambil Template `docker-compose.yml` (Fail-Closed, Zero-Host-Port & Shared DB)
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

### 6. Generate `.env` Lokal Aman untuk Developer
```bash
curl -sSL https://raw.githubusercontent.com/gokodingin/devops-standards/main/scripts/gen-dev-env.sh | bash
```

---

## 🚀 Reusable CI/CD Pipeline (Quality Gate -> Staging -> Production)

Seluruh project GoKodingin wajib memisahkan workflow CI (Automated Test & Compose Lint) dan CD (Deploy ke Staging / Production):

### Pasang Workflow di Project Baru:
```bash
mkdir -p .github/workflows

# 1. CI Quality Gatekeeper (Jalan di seluruh push branch / PR)
curl -sSL https://raw.githubusercontent.com/gokodingin/devops-standards/main/templates/ci.template.yml -o .github/workflows/ci.yml

# 2. CD Staging (Auto deploy saat push ke branch staging)
curl -sSL https://raw.githubusercontent.com/gokodingin/devops-standards/main/templates/cd-staging.template.yml -o .github/workflows/cd-staging.yml

# 3. CD Production (Auto deploy saat push ke branch main)
curl -sSL https://raw.githubusercontent.com/gokodingin/devops-standards/main/templates/cd-production.template.yml -o .github/workflows/cd-production.yml
```

---

## 🔐 GitHub Secrets & Environments yang Wajib Dikonfigurasi

Untuk keamanan isolasi rahasia (*least-privilege*), pisahkan konfigurasi rahasia ke level Repository dan level GitHub Environment:

### A. Repository Secrets (Koneksi Runner ke Server):
| Secret Name | Deskripsi | Nilai Contoh |
| :--- | :--- | :--- |
| **`TAILSCALE_AUTHKEY`** | Ephemeral Auth Key dari Tailscale Admin Console | `tskey-auth-kXXXXX-XXXXX` |
| **`SERVER_HOST`** | IP Tailscale server target | `100.101.0.48` |
| **`SERVER_USER`** | User SSH server | `deploy` atau `gokodingin` |
| **`SSH_PRIVATE_KEY`** | Private key SSH (`id_ed25519`) runner | `-----BEGIN OPENSSH PRIVATE KEY-----...` |
| **`SSH_KNOWN_HOSTS`** | Host key fingerprint server (cegah MITM) | Hasil `ssh-keyscan 100.101.0.48` |

### B. Environment Secrets (`production` dan `staging`):
Gunakan script `push-secrets.sh` untuk mengunggah file dotenv lokal tanpa membuka dashboard web:
```bash
./scripts/push-secrets.sh -r gokodingin/nama-repo -e production -f .env.production
```
Secret akan tersimpan sebagai **`APP_ENV`** di GitHub Environment terkait dan diinjeksi via stdin saat proses deploy ke server.

---

## 🛠️ Scripts & Utilities

- `scripts/push-secrets.sh`: Validasi dotenv lokal (mode 600, anti-dummy) dan sinkronisasi ke GitHub Environment secrets via `gh`.
- `scripts/lint-compose-secrets.sh`: CI gatekeeper untuk mendeteksi fallback secret dan plaintext credentials di file compose.
- `scripts/gen-dev-env.sh`: Generator file `.env` lokal developer dengan secret acak.
- `scripts/sync-npm-proxy.sh`: Script sinkronisasi NPM via REST API tahan injeksi (menggunakan `jq`).
- `server/gk-deploy.sh`: Entrypoint server SSH restricted forced-command untuk runner deploy.
- `scripts/check-proxy-mesh.sh`: Script diagnostik kesehatan jaringan internal Docker dan resolusi DNS antar container.
