# Panduan Multi-Stage Dockerfile & Docker Compose: Dev, Staging & Production

Dokumen ini adalah standar arsitektur containerization untuk project di lingkungan GoKodingin (server `100.101.0.48`). Tujuannya adalah memisahkan tahap **Development**, **Staging**, dan **Production** sehingga artifact staging & production:
1. **Ramping (Minimal Size)**: Tidak membawa build toolchain (GCC, python, make, git), devDependencies (`@types/*`, `vite`, `jest`, `eslint`, `ts-node`), map source, cache NPM/Yarn.
2. **Aman (Security Hardening)**: Menjalankan aplikasi dengan user non-root (`node` / `appuser`), base image distroless/alpine.
3. **Multi-Stage Targetting**: Menggunakan **1 buah Dockerfile** yang sama dengan `target:` berbeda di `docker-compose.yml`.

---

## 1. Template Multi-Stage Dockerfile (Node.js / TypeScript / React / Next)

Contoh aplikasi Node.js/TypeScript (Express, Nest, atau Fastify). Satu Dockerfile mencakup 4 stage: `base`, `development`, `build`, dan `production`:

```dockerfile
# ------------------------------------------------------------------------------
# Stage 1: Base (Common runtime dependencies & security)
# ------------------------------------------------------------------------------
FROM node:20-alpine AS base
WORKDIR /app
# Install dumb-init untuk menangani PID 1 & signal terminating (SIGTERM/SIGINT) dengan benar
RUN apk add --no-cache dumb-init
# Pisahkan package.json agar caching layer Docker optimal
COPY package.json package-lock.json* pnpm-lock.yaml* yarn.lock* ./

# ------------------------------------------------------------------------------
# Stage 2: Development (Digunakan untuk dev lokal: hot reload, linter, tests)
# ------------------------------------------------------------------------------
FROM base AS development
ENV NODE_ENV=development
# Install SEMUA dependencies (termasuk devDependencies)
RUN npm ci
# Source code di-mount lewat volume saat dev, atau dicopy jika container standalone
COPY . .
EXPOSE 3000
CMD ["npm", "run", "dev"]

# ------------------------------------------------------------------------------
# Stage 3: Builder (Compile TS/Vite/Assets & Prune devDependencies)
# ------------------------------------------------------------------------------
FROM base AS builder
ENV NODE_ENV=development
RUN npm ci
COPY . .
# Compile TypeScript -> dist/ atau Vite/Next.js -> build/
RUN npm run build
# Buang devDependencies, sisakan production dependencies saja
RUN npm prune --production

# ------------------------------------------------------------------------------
# Stage 4: Staging (Identik dengan Production tapi membawa staging env/debug tool)
# ------------------------------------------------------------------------------
FROM node:20-alpine AS staging
WORKDIR /app
ENV NODE_ENV=staging
RUN apk add --no-cache dumb-init curl
# Copy hanya production node_modules & build artifacts dari builder
COPY --from=builder /app/package.json ./
COPY --from=builder /app/node_modules ./node_modules
COPY --from=builder /app/dist ./dist
# Gunakan user non-root untuk keamanan
USER node
EXPOSE 3000
ENTRYPOINT ["/usr/bin/dumb-init", "--"]
CMD ["node", "dist/main.js"]

# ------------------------------------------------------------------------------
# Stage 5: Production (Ultra-slim, Zero devDependencies, Non-root)
# ------------------------------------------------------------------------------
FROM node:20-alpine AS production
WORKDIR /app
ENV NODE_ENV=production
RUN apk add --no-cache dumb-init
# Hapus package manager cache & temporary files
COPY --from=builder --chown=node:node /app/package.json ./
COPY --from=builder --chown=node:node /app/node_modules ./node_modules
COPY --from=builder --chown=node:node /app/dist ./dist

USER node
EXPOSE 3000
ENTRYPOINT ["/usr/bin/dumb-init", "--"]
CMD ["node", "dist/main.js"]
```

---

## 2. Template Multi-Stage Dockerfile (Frontend SPA: React / Vue / Vite + Nginx)

Untuk frontend SPA, artifact akhir production hanyalah static HTML/JS/CSS yang disajikan oleh Nginx Alpine (~25 MB total size container):

```dockerfile
# ------------------------------------------------------------------------------
# Stage 1: Base & Dev
# ------------------------------------------------------------------------------
FROM node:20-alpine AS dev
WORKDIR /app
COPY package.json package-lock.json* ./
RUN npm ci
COPY . .
EXPOSE 5173
CMD ["npm", "run", "dev", "--", "--host"]

# ------------------------------------------------------------------------------
# Stage 2: Build Artifacts
# ------------------------------------------------------------------------------
FROM dev AS builder
ARG MODE=production
ARG VITE_API_URL
ENV VITE_API_URL=$VITE_API_URL
RUN npm run build -- --mode $MODE

# ------------------------------------------------------------------------------
# Stage 3: Production Nginx Server (Hanya berisi web server & bundle static)
# ------------------------------------------------------------------------------
FROM nginx:alpine AS production
# Copy custom nginx conf untuk SPA (try_files $uri /index.html)
COPY nginx.conf /etc/nginx/conf.d/default.conf
# Copy hasil build static dari builder stage
COPY --from=builder /app/dist /usr/share/nginx/html
EXPOSE 80
CMD ["nginx", "-g", "daemon off;"]
```

---

## 3. Strategi Konfigurasi Docker Compose

Gunakan parameter `target:` pada build context Docker Compose untuk memilih stage yang diinginkan:

### A. `docker-compose.yml` (Production - Digunakan di Server Target)
```yaml
version: '3.8'

services:
  app:
    build:
      context: .
      dockerfile: Dockerfile
      target: production       # <--- Menargetkan stage production (ultra-slim)
    container_name: myapp_prod
    restart: unless-stopped
    expose:
      - "3000"                 # Port internal, tanpa bind host port
    environment:
      - NODE_ENV=production
      - PORT=3000
      - DATABASE_URL=${DATABASE_URL:-postgresql://gokodingin:GoKodingin2024@DB_POSTGRE:5432/myapp_prod}
    networks:
      - shared_network

  # Database fallback hanya menyala jika profil local-db dipanggil
  db:
    image: postgres:15-alpine
    profiles:
      - local-db
    environment:
      - POSTGRES_USER=postgres
      - POSTGRES_PASSWORD=postgres
      - POSTGRES_DB=myapp_prod
    networks:
      - shared_network

networks:
  shared_network:
    external: true
```

### B. `docker-compose.staging.yml` (Staging Environment di Server Target)
```yaml
version: '3.8'

services:
  app_staging:
    build:
      context: .
      dockerfile: Dockerfile
      target: staging          # <--- Menargetkan stage staging
    container_name: myapp_staging
    restart: unless-stopped
    expose:
      - "3000"
    environment:
      - NODE_ENV=staging
      - PORT=3000
      - DATABASE_URL=${DATABASE_URL:-postgresql://gokodingin:GoKodingin2024@DB_POSTGRE:5432/myapp_staging}
    networks:
      - shared_network

networks:
  shared_network:
    external: true
```

### C. `docker-compose.dev.yml` (Local Machine Developer)
```yaml
version: '3.8'

services:
  app_dev:
    build:
      context: .
      dockerfile: Dockerfile
      target: development      # <--- Menargetkan stage dev (lengkap dengan compiler/linter)
    container_name: myapp_dev
    ports:
      - "3000:3000"            # Bind ke localhost developer
    volumes:
      - .:/app                 # Hot-reloading: bind mount source code lokal
      - /app/node_modules      # Anonymous volume agar node_modules container tidak tertimpa host
    environment:
      - NODE_ENV=development
      - DATABASE_URL=postgresql://postgres:postgres@db_dev:5432/myapp_dev
    depends_on:
      - db_dev

  db_dev:
    image: postgres:15-alpine
    ports:
      - "5432:5432"
    environment:
      - POSTGRES_USER=postgres
      - POSTGRES_PASSWORD=postgres
      - POSTGRES_DB=myapp_dev
    volumes:
      - dev_db_data:/var/lib/postgresql/data

volumes:
  dev_db_data:
```

---

## 4. Standar Development: `docker-compose.dev.yml` (Live Mount & Zero-Rebuild)

Pendekatan eksplisit menggunakan file **`docker-compose.dev.yml`** adalah standar yang paling bersih, transparan, dan dapat disimpan di git repo untuk seluruh tim developer.

### Mengapa Menggunakan File Terpisah `docker-compose.dev.yml`?
1. **Pemisahan Konfigurasi yang Jelas**:
   - `docker-compose.yml` -> Standar **Production** di server (`target: production`, `expose:`, tanpa mount code host).
   - `docker-compose.staging.yml` -> Standar **Staging** di server (`target: production`, `expose:`).
   - `docker-compose.dev.yml` -> Standar **Development Lokal** (`target: development`, port forwarding ke host, live bind-mount).
2. **Version Controlled di Git**: File `docker-compose.dev.yml` disimpan langsung di repo sehingga developer baru tinggal clone repo dan langsung menjalankan satu perintah tanpa perlu membuat/mengcopy file override manual.

### Struktur Template Standar `docker-compose.dev.yml`:
```yaml
version: '3.8'

services:
  backend:
    build:
      context: ./backend
      dockerfile: Dockerfile
      target: development       # Stage dev: ada nodemon, ts-node, atau node --watch
    container_name: myapp_backend_dev
    ports:
      - "3000:3000"            # Bind ke localhost developer
    volumes:
      - ./backend:/app          # [LIVE MOUNT] Save code langsung terupdate di container
      - /app/node_modules       # [ANONYMOUS VOLUME] Mengisolasi dependensi Linux container
    command: npm run dev

  frontend:
    build:
      context: ./frontend
      dockerfile: Dockerfile
      target: development
    container_name: myapp_frontend_dev
    ports:
      - "5173:5173"            # Port Vite dev server
    volumes:
      - ./frontend:/app
      - /app/node_modules
    command: npm run dev -- --host
```

### Cara Menjalankan Development:
```bash
# Menjalankan development lokal dengan live reload:
docker compose -f docker-compose.dev.yml up

# Menjalankan di background:
docker compose -f docker-compose.dev.yml up -d

# Menghentikan container dev:
docker compose -f docker-compose.dev.yml down
```

### Manfaat Pola Ini untuk Semua Project:
- **Instan (Zero Rebuild)**: File disimpan (Ctrl+S), container langsung auto-reload via `node --watch` atau Vite HMR dalam milidetik.
- **Isolated Node Modules**: Anonymous volume `- /app/node_modules` memastikan folder `node_modules` host tidak merusak binary Linux di container.
- **Zero Conflict dengan Production**: File `docker-compose.yml` utama di server tetap 100% aman dan tidak terpengaruh oleh port localhost maupun bind-mount dev.
---

## 5. Checklist & Best Practices Perampingan Size Container

| Aspek | Praktik Buruk (Anti-Pattern) | Praktik Baik (Standard Multi-Stage) |
| :--- | :--- | :--- |
| **Base Image** | `node:20` (Ubuntu/Debian ~1 GB) | `node:20-alpine` (~180 MB) atau distroless |
| **Dependencies** | Membiarkan TypeScript, Vite, Jest, Webpack di production | `RUN npm prune --production` atau hanya copy `node_modules` runtime |
| **Source Files** | Menyalin file `.ts`, `.env.local`, `.git`, tests | Menambahkan `.dockerignore` ketat & hanya copy `dist/` hasil build |
| **Security** | Berjalan sebagai `root` | `USER node` atau `USER 1000:1000` |
| **Host Ports** | `ports: - "3000:3000"` (menyebabkan tabrakan port di server) | `expose: - "3000"` + terhubung ke `shared_network` (di-route oleh NPM) |

### Contoh File `.dockerignore` Wajib:
```gitignore
node_modules
dist
build
.git
.gitignore
.env*
!.env.example
*.md
coverage
tests
.vscode
.idea
Dockerfile*
docker-compose*
```

---

## 6. Ringkasan Perbandingan Ukuran Image Hasil Build

| Stage | Yang Termasuk | Estimasi Ukuran Image |
| :--- | :--- | :--- |
| **Development** | Source code, test runner, compiler TS, linter, devDependencies | ~650 MB – 1.1 GB |
| **Builder (Intermediary)** | Build toolchain, cache compiler | Dibuang otomatis oleh Docker build engine |
| **Staging** | Binary terkompilasi (`dist/`), production runtime modules, curl (debug tool) | ~190 MB – 240 MB |
| **Production** | Binary terkompilasi (`dist/`), production runtime modules only, dumb-init, non-root user | **~150 MB – 200 MB** (Turun >70%) |
| **Frontend Static (Nginx)** | HTML, CSS, JS bundle, Nginx Alpine | **~25 MB – 40 MB** |
