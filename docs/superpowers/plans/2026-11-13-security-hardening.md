# Devops Standards Security Hardening & Automation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Mengamankan repository `gokodingin/devops-standards` dengan menghilangkan kebocoran rahasia dan fallback rentan, menerapkan script otomasi secret sync, serta memperbarui reusable workflow dan template menjadi robust dan fail-closed.

**Architecture:** 
- Otomasi secrets menggunakan `push-secrets.sh` (`gh secret set --env`) untuk mengirim file `.env` lokal langsung ke GitHub Environment secrets tanpa pernah terekspose di argv atau logs.
- Compose fail-closed: variabel rahasia wajib menggunakan `${VAR:?pesan error}` dan divalidasi saat CI via `lint-compose-secrets.sh`.
- Deployment server dikunci menggunakan SSH forced-command (`gk-deploy.sh`), menerima commit SHA immutable dan payload env via stdin dengan validasi argumen ketat.
- Reusable workflows dipin menggunakan commit SHA lengkap dengan permission minimal `contents: read`.

**Tech Stack:** Bash, Docker, Docker Compose, GitHub Actions, Nginx, Nginx Proxy Manager REST API, PostgreSQL, Cloudflare Tunnel.

**Spec:** Hasil security audit di `~/security-audit-skill/devops-standards/run-1/REPORT.md`.

## Global Constraints
- Dilarang menyertakan kredensial plaintext, password dummy yang menyerupai credential nyata, atau token Cloudflare di dalam file git.
- Variabel rahasia (secret) tidak boleh menggunakan fallback default literal (`${VAR:-default_password}`) di environment non-lokal.
- Seluruh reusable workflow dan action pihak ketiga wajib dipin dengan 40-karakter commit SHA.
- Shell script wajib menggunakan `set -euo pipefail` dan validasi input regex ketat.

## Review Focus
1. **JSON Assembly di `sync-npm-proxy.sh`:** Karakter tanda kutip ganda (`"`) atau backslash (`\`) pada password atau input domain tidak boleh merusak payload JSON atau menginjeksi field tambahan.
2. **Pola Fail-Closed Compose:** Menjalankan `docker compose config` tanpa `.env` wajib menghasilkan error exit non-zero (gagal deploy jika secret absen).
3. **Validasi Argumen di `gk-deploy.sh`:** Percobaan injeksi karakter shell (misal `main; id` atau `../../etc/passwd`) pada parameter deploy wajib langsung digagalkan sebelum eksekusi.
4. **Kebocoran Argv:** Nilai password atau token rahasia dilarang diteruskan melalui argumen baris perintah (`argv`), melainkan melalui pipe stdin atau file header dengan permission `600`.
5. **Lockfile Integrity di CI:** CI tidak boleh melakukan fallback ke `npm install` jika `npm ci` gagal.

---

### Task 1: Sanitasi Dokumentasi & Hapus Rahasia Terekspose

**Files:**
- Modify: `docs/INFRA_ROUTING_STRATEGY.md`
- Modify: `docs/SHARED_DB_AND_CI_CD_STRATEGY.md`
- Modify: `docs/MULTI_STAGE_DOCKER_GUIDE.md`

- [ ] **Step 1: Sanitasi token Cloudflare di `docs/INFRA_ROUTING_STRATEGY.md`**
  Ganti baris `command: tunnel run --token eyJ...` dengan placeholder aman:
  `command: tunnel run --token ${CLOUDFLARE_TUNNEL_TOKEN:?Token Cloudflare wajib diisi}`.
- [ ] **Step 2: Hapus default password database `***REMOVED***` di seluruh dokumen**
  Ganti seluruh string `postgresql://gokodingin:***REMOVED***@DB_POSTGRE:5432/...` dengan sintaks variabel environment aman `postgresql://${DB_USER}:${DB_PASSWORD}@DB_POSTGRE:5432/${DB_NAME}` atau `${DATABASE_URL:?DATABASE_URL wajib diisi}`.
- [ ] **Step 3: Verifikasi tidak ada sisa password atau token di file docs**
  Jalankan grep untuk memastikan string `***REMOVED***` dan token base64 `eyJ...` sudah bersih dari direktori `docs/`.
- [ ] **Step 4: Commit**
  `git commit -m "docs: sanitize leaked cloudflare token and database passwords"`

---

### Task 2: Script Otomasi & CI Gatekeepers

**Files:**
- Create: `scripts/push-secrets.sh`
- Create: `scripts/lint-compose-secrets.sh`
- Create: `scripts/gen-dev-env.sh`
- Modify: `scripts/sync-npm-proxy.sh`
- Create: `server/gk-deploy.sh`

- [ ] **Step 1: Implementasi `scripts/push-secrets.sh`**
  Script untuk memvalidasi file `.env` lokal (permission 600, tidak terlacak git, tidak ada nilai default/dummy), lalu mengunggahnya sebagai secret `APP_ENV` ke GitHub Environment via `gh secret set --env`.
- [ ] **Step 2: Implementasi `scripts/lint-compose-secrets.sh`**
  Linter CI untuk mendeteksi fallback secret (`${VAR:-literal}`), password hardcoded dalam URL, atau assignment literal secret.
- [ ] **Step 3: Implementasi `scripts/gen-dev-env.sh`**
  Script pembuat `.env` lokal otomatis berisi random JWT_SECRET dan DB credentials untuk developer laptop.
- [ ] **Step 4: Hardening `scripts/sync-npm-proxy.sh`**
  Ganti perakitan heredoc dengan `jq` murni, gunakan stdin untuk token autentikasi, serta validasi regex untuk domain dan container hostname.
- [ ] **Step 5: Implementasi `server/gk-deploy.sh`**
  Entrypoint server SSH restricted forced-command yang menerima commit SHA 40-karakter, memverifikasi seluruh argumen, menginjeksi `.env` via stdin, dan memicu `docker compose up -d`.
- [ ] **Step 6: Uji sintaks dan fungsionalitas seluruh script**
  Jalankan `bash -n scripts/*.sh server/*.sh` dan tes linter terhadap template compose.
- [ ] **Step 7: Commit**
  `git commit -m "feat(scripts): add secret sync automation, compose linter, and hardened deploy entrypoint"`

---

### Task 3: Hardening Reusable CI/CD Workflows

**Files:**
- Modify: `.github/workflows/reusable-deploy.yml`
- Modify: `.github/workflows/reusable-test.yml`

- [ ] **Step 1: Perbarui `.github/workflows/reusable-deploy.yml`**
  - Pin semua action ke commit SHA spesifik (`tailscale/github-action`, dll).
  - Terapkan `permissions: { contents: read }`.
  - Gunakan GitHub Environments untuk mengisolasi secret.
  - Hilangkan interpolasi ekspresi GitHub Actions langsung ke shell script; gunakan environment variables.
  - Gunakan `SSH_KNOWN_HOSTS` untuk mencegah serangan MITM.
  - Teruskan payload `APP_ENV` via stdin ke perintah forced-command.
- [ ] **Step 2: Perbarui `.github/workflows/reusable-test.yml`**
  - Hapus fallback `npm install` (wajib `npm ci --ignore-scripts`).
  - Tambahkan audit keamanan dependencies `npm audit --audit-level=high`.
  - Jalankan `scripts/lint-compose-secrets.sh` sebagai gatekeeper.
  - Validasi seluruh file compose menggunakan dummy environment file.
- [ ] **Step 3: Verifikasi sintaks workflow YAML**
  Gunakan parser YAML python untuk memverifikasi struktur file workflow valid.
- [ ] **Step 4: Commit**
  `git commit -m "ci: harden reusable test and deploy workflows with sha pinning and strict validation"`

---

### Task 4: Pembaruan Template Docker & Docker Compose

**Files:**
- Modify: `templates/docker-compose.template.yml`
- Modify: `templates/docker-compose.dev.template.yml`
- Modify: `templates/docker-compose.local.template.yml`
- Modify: `templates/Dockerfile.node`
- Modify: `templates/Dockerfile.spa`
- Modify: `templates/cd-development.template.yml`
- Modify: `templates/cd-staging.template.yml`
- Modify: `templates/cd-production.template.yml`
- Modify: `templates/ci.template.yml`

- [ ] **Step 1: Perbarui templates compose menjadi fail-closed**
  Ganti default literal pada rahasia dengan `${VAR:?VAR wajib diisi}`.
  Tambahkan `read_only: true`, `tmpfs`, `cap_drop: [ALL]`, dan `security_opt: ["no-new-privileges:true"]` pada template produksi.
- [ ] **Step 2: Perbarui templates Dockerfile**
  Tambahkan HEALTHCHECK bawaan, pastikan SPA menggunakan `nginx-unprivileged`, dan hilangkan dependensi build di stage produksi.
- [ ] **Step 3: Perbarui template CD workflow**
  Ganti `secrets: inherit` dengan pemetaan eksplisit rahasia per-environment dan referensi commit SHA.
- [ ] **Step 4: Uji validitas template compose dengan `docker compose config`**
- [ ] **Step 5: Commit**
  `git commit -m "feat(templates): implement fail-closed compose configurations and hardened containers"`

---

### Task 5: Pembaruan Panduan Dokumentasi (README & Guide)

**Files:**
- Modify: `README.md`
- Create: `docs/SECRET_MANAGEMENT_AND_SECURITY.md`

- [ ] **Step 1: Buat panduan komprehensif `docs/SECRET_MANAGEMENT_AND_SECURITY.md`**
  Jelaskan alur manajemen secret:
  1. Cara menggunakan `scripts/push-secrets.sh` untuk sinkronisasi secret ke GitHub Environments.
  2. SOP rotasi kredensial jika terjadi insiden.
  3. Konfigurasi SSH forced-command di server target (`~/.ssh/authorized_keys`).
- [ ] **Step 2: Perbarui `README.md`**
  - Tambahkan ringkasan arsitektur keamanan baru.
  - Perbaiki tautan template yang hilang (`pipeline.template.yml`).
  - Dokumentasikan cara kerja GitHub Environment dan CI secret gatekeeper.
- [ ] **Step 3: Commit**
  `git commit -m "docs: add comprehensive secret management guide and update README"`
