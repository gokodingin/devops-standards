# Arsitektur Routing: Wildcard Cloudflare Tunnel -> Nginx Proxy Manager (NPM)

Dokumen ini menjelaskan arsitektur routing terpusat di server `100.101.0.48`, pola zero-host-port exposure, pemetaan container existing, serta SOP penambahan subdomain baru.

---

## 1. Topologi Jaringan

```
[ Client / Browser ]
        │ (HTTPS)
        ▼
[ Cloudflare Edge ]
  - DNS: * (CNAME) -> <tunnel-id>.cfargotunnel.com (Proxied)
  - Edge Rule: Subdomain * -> http://nginx-proxy-manager-app-1:80
        │ (Encrypted Tunnel: QUIC / HTTP2)
        ▼
[ cloudflared-tunnel ] (Docker container)
        │ (Internal Docker Network: npm_network / shared_network)
        ▼
[ nginx-proxy-manager-app-1:80 ] (NPM)
        │ (Internal Docker Network: shared_network)
        ▼
[ Application Containers ] (home_storage_nginx:80, dashboard-crm-app-1:80, dll)
```

### Keunggulan Arsitektur:
1. **Zero Host Port Collision**: Project baru tidak perlu membuka port di host (`ports: - "xxxx:80"`). Cukup gunakan `expose: ["80"]` atau `expose: ["3000"]`.
2. **Sentralisasi Routing**: Menambah atau mengubah project/subdomain cukup lewat Web UI Nginx Proxy Manager (`http://100.101.0.48:81`), tanpa mengubah konfigurasi Cloudflare Zero Trust berulang kali.
3. **Anti-Redirect Loop**:
   - SSL diterminasi di Cloudflare Edge.
   - Trafik dari `cloudflared-tunnel` masuk ke NPM via HTTP port `80`.
   - Di Proxy Host NPM, **Force SSL = OFF**. Cloudflare mengelola redirect HTTPS via fitur **Always Use HTTPS**.

---

## 2. Pemetaan Layanan & Port Internal

Semua container berikut terhubung ke `shared_network` (bridge network Docker) dan dapat di-proxy langsung menggunakan container name & port internal:

| Domain / Subdomain | Forward Host (Container Name) | Internal Port | Status Routing NPM |
| :--- | :--- | :--- | :--- |
| `storage.gokodingin.com` | `home_storage_nginx` | `80` | Aktif (Proxy Host #7) |
| `storage-staging.gokodingin.com` | `home_storage_nginx_staging` | `80` | Siap didaftarkan |
| `dashboard.gokodingin.com` | `dashboard-crm-app-1` | `80` | Siap dialihkan |
| `printmanagement.gokodingin.com` | `print-prod-app-1` | `80` | Siap dialihkan |
| `demoprint.gokodingin.com` | `print-management-demo-app` | `80` | Siap dialihkan |
| `www.gokodingin.com` | `lp-gokodingin-prod` | `3000` | Siap dialihkan |
| `lms-api.gokodingin.my.id` | `lms-aggregator-api-prod` | `3001` | Siap dialihkan |
| `devices.gokodingin.com` (opsional) | `be-remote-device` | `8080` | Siap dialihkan |

---

## 3. Konfigurasi Cloudflare Zero Trust (Dual Tunnel Architecture)

Berdasarkan dashboard Cloudflare Zero Trust, server ini terhubung ke **2 Tunnel terpisah**:

1. **Tunnel 1: `home-server`** (ID: `c0af4d68-5d9a-4a32-b512-9a0fdbce0fcb`)
   - **Runner**: Docker container `cloudflared-tunnel` di server `100.101.0.48`.
   - **Domain Utama**: `gokodingin.com` (dan transisi `lms-api.gokodingin.my.id`).
   - **Target**: Dihubungkan ke `http://nginx-proxy-manager-app-1:80` untuk routing terpusat wildcard `*.gokodingin.com`.

2. **Tunnel 2: `orange-server`** (ID: `2323eeb8-a739-4959-aa17-ced4d3494df7`)
   - **Runner**: Embedded process di container `uptime-kuma` (PID `7605` di server `100.101.0.48`).
   - **Domain Utama**: `*.gokodingin.my.id` (`home`, `portainer`, `api-warehouse`, `dashboard`, `mc`, `serv-db`).

---

### Strategi Routing untuk Masing-Masing Tunnel

#### A. Untuk Domain `gokodingin.com` (Tunnel `home-server`):
1. Buka **Cloudflare Zero Trust** -> **Networks** -> **Tunnels** -> Pilih `home-server` -> **Configure** -> **Public Hostname**.
2. Tambahkan **Wildcard Rule** di posisi paling bawah:
   - **Subdomain**: `*`
   - **Domain**: `gokodingin.com`
   - **Type**: `HTTP`
   - **URL**: `http://nginx-proxy-manager-app-1:80`
3. Di **Cloudflare DNS Management** untuk `gokodingin.com`:
   - Tambahkan CNAME record:
     - **Type**: `CNAME`
     - **Name**: `*`
     - **Target**: `c0af4d68-5d9a-4a32-b512-9a0fdbce0fcb.cfargotunnel.com`
     - **Proxy status**: `Proxied` (Orange Cloud)
   - Pastikan **SSL/TLS -> Edge Certificates -> Always Use HTTPS** aktif.

#### B. Untuk Domain `gokodingin.my.id` (Pilihan 1 vs Pilihan 2):

- **Pilihan 1 (Konsolidasi ke NPM - Direkomendasikan jika ingin seragam)**:
  1. Di Tunnel `orange-server` -> **Public Hostname**:
     - Tambahkan rule wildcard:
       - **Subdomain**: `*`
       - **Domain**: `gokodingin.my.id`
       - **Type**: `HTTP`
       - **URL**: `http://100.101.0.48:80` (karena tunnel `orange-server` berjalan di dalam container `uptime-kuma`, akses ke NPM via IP server `100.101.0.48:80`).
  2. Di DNS `gokodingin.my.id`: CNAME `*` -> `2323eeb8-a739-4959-aa17-ced4d3494df7.cfargotunnel.com`.
  3. Kelola seluruh subdomain `*.gokodingin.my.id` lewat Proxy Host di NPM UI (`http://100.101.0.48:81`).

- **Pilihan 2 (Pertahankan Terpisah)**:
  - Biarkan Tunnel `orange-server` tetap melayani route spesifik internal yang ada (`portainer`, `serv-db`, dll) seperti di screenshot tanpa wildcard, sementara wildcard NPM dikhususkan untuk `*.gokodingin.com` di Tunnel `home-server`.
## 4. Konfigurasi Persisten Stack NPM & Cloudflared di Portainer

Agar koneksi ke `shared_network` tidak hilang saat stack di-redeploy di Portainer, perbarui konfigurasi compose stack terkait:

### Stack Nginx Proxy Manager (Portainer Stack #21)
```yaml
version: '3.8'

services:
  app:
    image: 'jc21/nginx-proxy-manager:latest'
    restart: unless-stopped
    ports:
      - '80:80'
      - '81:81'
      - '443:443'
    volumes:
      - ./data:/data
      - ./letsencrypt:/etc/letsencrypt
    networks:
      - npm_network
      - shared_network

networks:
  npm_network:
    external: true
  shared_network:
    external: true
```

### Stack Cloudflare Tunnel (Portainer Stack #33)
```yaml
version: '3.8'

services:
  tunnel:
    container_name: cloudflared-tunnel
    image: cloudflare/cloudflared:latest
    restart: always
    command: tunnel run --token ***REMOVED***
    networks:
      - npm_network
      - shared_network

networks:
  npm_network:
    external: true
  shared_network:
    external: true
```

---

## 5. Template Standar `docker-compose.yml` untuk Project Baru

Setiap project baru cukup menghubungkan service ke `shared_network` tanpa memetakan port ke host machine:

```yaml
version: '3.8'

services:
  my-app:
    build: .
    container_name: my-new-project-app
    restart: unless-stopped
    expose:
      - "3000"              # Port internal aplikasi, BUKAN ports: - "3000:3000"
    networks:
      - shared_network

networks:
  shared_network:
    external: true
```

---

## 6. SOP 2 Langkah Menambah Subdomain Baru

Setelah aplikasi di-deploy (`docker compose up -d`):

1. **Buka Web UI NPM**:
   - URL: `http://100.101.0.48:81`
2. **Tambahkan Proxy Host**:
   - **Domain Names**: `<subdomain>.gokodingin.com` (misal: `api.gokodingin.com`)
   - **Scheme**: `http`
   - **Forward Hostname / IP**: `<nama_container>` (misal: `my-new-project-app`)
   - **Forward Port**: `<port_internal>` (misal: `3000`)
   - **Block Common Exploits**: Centang / Aktifkan.
   - **Tab SSL**:
     - Certificate: Pilih Custom Origin Cert `npm-18` atau `None`.
     - **Force SSL**: **OFF** (Penting: cegah redirect loop).
   - Klik **Save**.
3. Subdomain langsung aktif dan dapat diakses publik dengan HTTPS otomatis melalui Cloudflare Edge.
