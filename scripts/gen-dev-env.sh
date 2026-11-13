#!/usr/bin/env bash
# scripts/gen-dev-env.sh
# Create a developer-local .env with random secrets (replaces committed "dev_jwt_secret_key_12345" defaults).
set -euo pipefail
umask 077
TARGET_FILE="${1:-.env}"
if [[ -e "$TARGET_FILE" ]]; then
  echo "$TARGET_FILE already exists, skipping generation."
  exit 0
fi
rand() { head -c 32 /dev/urandom | base64 | tr -d '/+=\n'; }
cat > "$TARGET_FILE" <<EOF
NODE_ENV=development
PORT=3000
DATABASE_URL=postgresql://gokodingin:$(rand)@localhost:5432/myapp_dev
STORAGE_ROOT=/var/storage
JWT_SECRET=$(rand)
JWT_EXPIRES_IN=24h
CORS_ORIGIN=http://localhost:5173
EOF
chmod 600 "$TARGET_FILE"
if [ -f .gitignore ]; then
  grep -qxF "$TARGET_FILE" .gitignore 2>/dev/null || echo "$TARGET_FILE" >> .gitignore
fi
echo "Generated secure developer environment file: $TARGET_FILE (mode 600)"
