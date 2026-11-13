# Panduan Manajemen Rahasia (Secrets) & Keamanan CI/CD GoKodingin

Dokumen ini adalah standar operasional dan panduan arsitektur keamanan untuk mengelola variabel rahasia (*environment secrets*), deployment zero-trust, serta mitigasi kebocoran kredensial di seluruh proyek GoKodingin.

---

## 1. Prinsip Utama: *Fail-Closed Zero-Fallback Secrets*

### Masalah dengan Fallback Default (`${VAR:-literal}`)
Pola lama yang sering dipakai di Docker Compose:
```yaml
# ❌ ANTI-PATTERN FATAL (FAIL-OPEN)
DATABASE_URL: ${DATABASE_URL:-postgresql://gokodingin:password@DB_POSTGRE:5432/myapp_prod}
JWT_SECRET: ${JWT_SECRET:-dev_jwt_secret_key_12345}
```
Ketika variabel environment tidak disuplai di server produksi, Docker Compose **secara diam-diam memakai password default yang tercatat di repositori publik/git**. Akibatnya, aplikasi menyala dengan rahasia yang sudah bocor tanpa ada peringatan atau kegagalan deploy.

### Solusi Standar Baru (`${VAR:?pesan error}`)
Seluruh template produksi dan staging **wajib** menggunakan sintaks *fail-closed*:
```yaml
# ✅ STANDAR GO KODINGIN (FAIL-CLOSED)
DATABASE_URL: ${DATABASE_URL:?DATABASE_URL wajib diisi via secret}
JWT_SECRET: ${JWT_SECRET:?JWT_SECRET wajib diisi via secret}
```
Jika secret belum diset di GitHub Environment atau di file `.env` server, proses deployment **langsung berhenti (fail-closed)** dengan pesan error eksplisit dan container tidak akan pernah menyala dengan rahasia kosong.

---

## 2. Alur Otomasi Secret: `push-secrets.sh`

Untuk menyederhanakan pengisian secret ke GitHub tanpa membuka Dashboard web satu per satu dan tanpa risiko rahasia terekam di riwayat shell (`history`) atau process list (`ps`), gunakan script:

```bash
# Lokasi: scripts/push-secrets.sh
./scripts/push-secrets.sh -r gokodingin/nama-repo -e production -f .env.production
```

### Parameter:
- `-r <owner/repo>`: Nama repositori target di GitHub.
- `-e <environment>`: Nama GitHub Environment (`development`, `staging`, `production`).
- `-f <file>`: File dotenv lokal (misal: `.env.production`).
- `-k <file>` (opsional): File daftar key wajib (misal: `.env.example`).
- `-n` (opsional): Dry-run mode untuk validasi saja tanpa mengirim.

### Aturan Keamanan yang Diterapkan oleh Script:
1. **File Permission 600**: Script menolak file yang dapat dibaca user lain (`chmod 644`). File wajib memiliki hak akses `600` (`chmod 600 .env.production`).
2. **Git-Tracked Rejection**: Script menolak mengeksekusi jika file tersebut tidak sengaja terlacak oleh Git (`git ls-files`).
3. **Anti-Dummy Validation**: Script otomatis mendeteksi dan menolak nilai placeholder berbahaya seperti `changeme`, `secret`, `password`, `dev_*`, `local_*`.
4. **Zero Argv Exposure**: Seluruh isi rahasia diunggah sebagai satu kesatuan payload `APP_ENV` via standard input (`stdin`) langsung ke GitHub API via `gh`.

---

## 3. Isolasi Runner & Server via SSH Forced-Command (`gk-deploy.sh`)

Untuk mencegah kompromi runner GitHub Actions berubah menjadi *arbitrary remote code execution* (RCE) dengan hak akses root di server, server mengunci kunci SSH deploy runner ke sebuah gatekeeper script.

### Cara Memasang di Server Target (`100.101.0.48`):

1. **Salin Script ke Server**:
   ```bash
   sudo cp server/gk-deploy.sh /usr/local/sbin/gk-deploy
   sudo chmod 755 /usr/local/sbin/gk-deploy
   sudo chown root:root /usr/local/sbin/gk-deploy
   ```

2. **Buat Konfigurasi Opsional (`/etc/gk-deploy.conf`)**:
   ```bash
   sudo cat > /etc/gk-deploy.conf << 'EOF'
   GH_OWNER="gokodingin"
   BASE_DIR="/home/gokodingin/apps"
   ALLOWED_SUFFIXES=".gokodingin.com .gokodingin.my.id"
   NPM_HOST="http://127.0.0.1:81"
   NPM_EMAIL="gokodingin@gmail.com"
   NPM_PASSWORD_FILE="/etc/npm-api.secret"
   PG_ADMIN_USER="postgres"
   EOF
   sudo chmod 600 /etc/gk-deploy.conf
   ```

3. **Kunci SSH Key di `~/.ssh/authorized_keys`**:
   Tambahkan opsi `command` dan `restrict` di depan public key runner GitHub Actions:
   ```text
   command="/usr/local/sbin/gk-deploy",restrict,from="100.64.0.0/10" ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAI... gha-deploy-key
   ```
   - `command="/usr/local/sbin/gk-deploy"`: Runner **hanya** diizinkan menjalankan script ini. Upaya menjalankan `ssh server "bash -i"` atau `cat /etc/shadow` akan ditolak.
   - `restrict`: Mematikan PTY allocation, port forwarding, X11 forwarding, dan SSH agent forwarding.
   - `from="100.64.0.0/10"`: Membatasi koneksi hanya dari subnet internal Tailscale.

---

## 4. SOP Emergency: Rotasi Kredensial & Pembersihan

### A. Rotasi Token Cloudflare Tunnel
Jika token Cloudflare Tunnel terekspose di repositori atau log:
1. Buka [Cloudflare Zero Trust Dashboard](https://one.dash.cloudflare.com/) -> **Networks** -> **Tunnels**.
2. Pilih Tunnel yang terdampak (`home-server` atau `orange-server`).
3. Klik tab **Manage** / **Configure** -> pilih **Reset / Rotate Token**.
4. Perbarui token baru pada stack Portainer / Docker host:
   ```bash
   docker restart cloudflared-tunnel
   ```

### B. Rotasi Password Database PostgreSQL
1. Masuk ke server host:
   ```bash
   docker exec -it DB_POSTGRE psql -U postgres
   ```
2. Ubah password user:
   ```sql
   ALTER USER gokodingin WITH PASSWORD 'Password_Baru_Yang_Kuat_32_Karakter!';
   ```
3. Update secret repositori menggunakan `./scripts/push-secrets.sh`.
4. Trigger deploy ulang di GitHub Actions agar file `.env` aplikasi diperbarui.

---

## 5. Ringkasan Secrets yang Wajib di GitHub Repositories

| Nama Secret | Scope | Deskripsi |
| :--- | :--- | :--- |
| `TAILSCALE_AUTHKEY` | Repo / Org Secret | Kunci Ephemeral Tailscale (tag `tag:ci`) |
| `SERVER_HOST` | Repo Secret | IP Tailscale server target (`100.101.0.48`) |
| `SERVER_USER` | Repo Secret | User SSH server (`deploy` atau `gokodingin`) |
| `SSH_PRIVATE_KEY` | Repo Secret | Private key SSH runner |
| `SSH_KNOWN_HOSTS` | Repo Secret | Output `ssh-keyscan` server untuk proteksi MITM |
| `APP_ENV` | **Environment Secret** (`production`/`staging`) | Konten utuh `.env` yang dipush via `push-secrets.sh` |
