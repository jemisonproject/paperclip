#!/usr/bin/env bash
# Paperclip container entrypoint.
#
# Responsibilities:
#   1. Initialize embedded PostgreSQL on first boot.
#   2. Start the Postgres daemon and wait until it's accepting connections.
#   3. Run migrations (if upstream provides a migrate script).
#   4. Hand off to the Paperclip server process.
#
# All state lives under /data which Railway mounts as a persistent volume.

set -euo pipefail

PGDATA="${PGDATA:-/data/pgdata}"
PG_USER="paperclip"
PG_DB="paperclip"
PG_PASS="paperclip"

# Use the highest PostgreSQL version installed in this image.
PG_BIN="$(ls -d /usr/lib/postgresql/*/bin 2>/dev/null | sort -V | tail -n1)"
if [ -z "${PG_BIN}" ]; then
  echo "ERROR: PostgreSQL binaries not found." >&2
  exit 1
fi
export PATH="${PG_BIN}:${PATH}"

mkdir -p "${PGDATA}"
chown -R postgres:postgres "${PGDATA}"
chmod 700 "${PGDATA}"

# 1. Initialize cluster on first boot.
if [ ! -s "${PGDATA}/PG_VERSION" ]; then
  echo "==> Initializing PostgreSQL cluster at ${PGDATA}"
  su - postgres -c "${PG_BIN}/initdb -D ${PGDATA} --encoding=UTF8 --locale=C"
  # Localhost only — keeps the embedded DB invisible to the public domain.
  echo "listen_addresses = 'localhost'" >> "${PGDATA}/postgresql.conf"
fi

# 2. Start postgres in the background.
echo "==> Starting PostgreSQL"
su - postgres -c "${PG_BIN}/pg_ctl -D ${PGDATA} -l ${PGDATA}/postgres.log -w start"

# 3. Create role/db on first boot.
if ! su - postgres -c "psql -tAc \"SELECT 1 FROM pg_roles WHERE rolname='${PG_USER}'\"" | grep -q 1; then
  echo "==> Creating role and database"
  su - postgres -c "psql -c \"CREATE ROLE ${PG_USER} WITH LOGIN PASSWORD '${PG_PASS}';\""
  su - postgres -c "psql -c \"CREATE DATABASE ${PG_DB} OWNER ${PG_USER};\""
fi

# 4. Run migrations if upstream defines one.
cd /app
if npm run --silent | grep -qE "^\s+(migrate|db:migrate|migration:run)\b"; then
  echo "==> Running database migrations"
  npm run migrate --if-present || \
  npm run db:migrate --if-present || \
  npm run migration:run --if-present || true
fi

# 5. Start the server in the foreground. Try common entry points.
echo "==> Starting Paperclip on port ${PORT:-3000}"
if npm run --silent | grep -qE "^\s+start\b"; then
  exec npm run start
elif [ -f "dist/index.js" ]; then
  exec node dist/index.js
elif [ -f "build/index.js" ]; then
  exec node build/index.js
elif [ -f "index.js" ]; then
  exec node index.js
else
  echo "ERROR: Could not find Paperclip entry point. Check upstream package.json." >&2
  exit 1
fi
