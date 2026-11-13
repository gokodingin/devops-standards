#!/usr/bin/env bash
# server/gk-deploy.sh
# Server-side deployment gatekeeper entrypoint for SSH forced-command.
# Install at /usr/local/sbin/gk-deploy (chmod 755 root:root)
# Add to ~/.ssh/authorized_keys:
# command="/usr/local/sbin/gk-deploy",restrict,from="100.64.0.0/10" ssh-ed25519 AAA... gha-deploy-key
#
# Client invocation:
# ssh deploy@server "deploy <repo> <sha40> <compose_file> <domain> <container> <port> <db_type> <db_name>" < env_payload
# Stdin carries the encrypted/secret .env payload, never exposed in command args.

set -euo pipefail
umask 077

CONF="${GK_CONF:-/etc/gk-deploy.conf}"
# Configuration can define: GH_OWNER, BASE_DIR, ALLOWED_SUFFIXES, NPM_HOST, NPM_EMAIL, NPM_PASSWORD_FILE, PG_ADMIN_USER
# shellcheck disable=SC1090
[[ -r "$CONF" ]] && . "$CONF"

: "${GH_OWNER:=gokodingin}"
: "${BASE_DIR:=/home/gokodingin/apps}"
: "${PG_ADMIN_USER:=postgres}"

DRY="${GK_DRY_RUN:-0}"

die() {
    echo "gk-deploy error: $*" >&2
    exit 2
}

run() {
    if [[ "$DRY" == 1 ]]; then
        echo "DRY_RUN: $*"
    else
        "$@"
    fi
}

# Parse original command from SSH
RAW_CMD="${SSH_ORIGINAL_COMMAND:-$*}"
read -r -a ARGS <<< "$RAW_CMD"

if [[ "${ARGS[0]:-}" != "deploy" || ${#ARGS[@]} -ne 9 ]]; then
    die "usage: deploy <repo> <sha> <compose_file> <domain> <container> <port> <db_type> <db_name>"
fi

REPO="${ARGS[1]}"
SHA="${ARGS[2]}"
COMPOSE="${ARGS[3]}"
DOMAIN="${ARGS[4]}"
CONTAINER="${ARGS[5]}"
PORT="${ARGS[6]}"
DB_TYPE="${ARGS[7]}"
DB_NAME="${ARGS[8]}"

# 1. Strict Parameter Validations
[[ "$REPO" =~ ^[A-Za-z0-9_.-]{1,100}$ && "$REPO" != .* ]] || die "Invalid repository name: $REPO"
[[ "$SHA" =~ ^[0-9a-f]{40}$ ]] || die "Invalid SHA: must be 40-character hex commit"
[[ "$COMPOSE" =~ ^docker-compose(\.[a-z]+)?\.ya?ml$ ]] || die "Invalid compose file: $COMPOSE"
[[ "$DOMAIN" =~ ^([a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?\.)+[a-z]{2,}$ ]] || die "Invalid domain format: $DOMAIN"
[[ "$CONTAINER" =~ ^[A-Za-z0-9][A-Za-z0-9_.-]{0,127}$ ]] || die "Invalid container name: $CONTAINER"
[[ "$PORT" =~ ^[0-9]{1,5}$ ]] && (( PORT >= 1 && PORT <= 65535 )) || die "Invalid port: $PORT"
[[ "$DB_TYPE" =~ ^(postgres|mariadb|none)$ ]] || die "Invalid db_type: $DB_TYPE (must be postgres, mariadb, or none)"
[[ "$DB_NAME" =~ ^([a-z][a-z0-9_]{0,62}|-)$ ]] || die "Invalid db_name: $DB_NAME ('-' for none)"

if [[ -n "${ALLOWED_SUFFIXES:-}" ]]; then
    matched=0
    for s in $ALLOWED_SUFFIXES; do
        if [[ "$DOMAIN" == *"$s" || "$DOMAIN" == "${s#.}" ]]; then
            matched=1
            break
        fi
    done
    if (( matched == 0 )); then
        die "Domain $DOMAIN is outside allowed suffixes ($ALLOWED_SUFFIXES)"
    fi
fi

APP_DIR="$BASE_DIR/$REPO"
mkdir -p "$BASE_DIR"

echo "=== [1/4] Checkout $REPO @ ${SHA:0:12} ==="
if [[ ! -d "$APP_DIR/.git" ]]; then
    run git clone --quiet "git@github.com:$GH_OWNER/$REPO.git" "$APP_DIR"
fi

if [[ "$DRY" != 1 ]]; then
    cd "$APP_DIR"
fi
run git fetch --quiet origin
run git checkout --quiet --detach "$SHA"

echo "=== [2/4] Menyiapkan Environment File (.env) ==="
if [[ ! -t 0 ]]; then
    TMP_ENV=$(mktemp "$APP_DIR/.env.XXXXXX" 2>/dev/null || mktemp)
    cat > "$TMP_ENV"
    if [[ -s "$TMP_ENV" ]]; then
        # Validate that payload only contains valid dotenv lines
        if grep -qvE '^\s*(#.*|[A-Z][A-Z0-9_]*=.*|)$' "$TMP_ENV"; then
            rm -f "$TMP_ENV"
            die "Environment payload contains invalid lines"
        fi
        if [[ "$DRY" == 1 ]]; then
            echo "DRY_RUN: Would write .env ($(grep -cE '^[A-Z]' "$TMP_ENV") keys)"
            rm -f "$TMP_ENV"
        else
            chmod 600 "$TMP_ENV"
            mv -f "$TMP_ENV" "$APP_DIR/.env"
        fi
    else
        rm -f "$TMP_ENV"
    fi
fi

echo "=== [3/4] Memeriksa & Menyiapkan Shared Database ==="
if [[ "$DB_TYPE" == "postgres" && "$DB_NAME" != "-" ]]; then
    echo "Ensuring postgres database $DB_NAME exists..."
    if [[ "$DRY" == 1 ]]; then
        echo "DRY_RUN: psql create database if missing: $DB_NAME"
    else
        printf "%s\n" "SELECT format('CREATE DATABASE %I', :'db') WHERE NOT EXISTS (SELECT 1 FROM pg_database WHERE datname = :'db') \\gexec" \
            | docker exec -i DB_POSTGRE psql -U "$PG_ADMIN_USER" -d postgres -v ON_ERROR_STOP=1 -v db="$DB_NAME"
    fi
elif [[ "$DB_TYPE" == "mariadb" && "$DB_NAME" != "-" ]]; then
    echo "Ensuring mariadb database $DB_NAME exists..."
    if [[ "$DRY" == 1 ]]; then
        echo "DRY_RUN: mysql create database if missing: $DB_NAME"
    else
        docker exec -i mariadb_server mysql -u root -e "CREATE DATABASE IF NOT EXISTS \`$DB_NAME\`;"
    fi
fi

echo "=== [4/4] Menjalankan Docker Compose & Sinkronisasi NPM ==="
COMPOSE_TAG=$(echo "$COMPOSE" | sed -E 's/^docker-compose\.?//; s/\.ya?ml$//' | tr -cd 'a-z0-9_-')
if [[ -z "$COMPOSE_TAG" || "$COMPOSE_TAG" == "yml" || "$COMPOSE_TAG" == "yaml" ]]; then
    PROJECT_NAME="${REPO}-prod"
else
    PROJECT_NAME="${REPO}-${COMPOSE_TAG}"
fi

run docker compose -p "$PROJECT_NAME" -f "$COMPOSE" up -d --build --remove-orphans

if [[ -n "${NPM_HOST:-}" && -f "${NPM_PASSWORD_FILE:-}" ]]; then
    NPM_PASS=$(cat "$NPM_PASSWORD_FILE")
    NPM_HOST="$NPM_HOST" NPM_EMAIL="$NPM_EMAIL" NPM_PASSWORD="$NPM_PASS" \
        run /usr/local/bin/sync-npm-proxy "$DOMAIN" "$CONTAINER" "$PORT"
fi

echo "Deployment for $REPO ($SHA) completed successfully."
