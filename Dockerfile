# syntax=docker/dockerfile:1.6
#
# Paperclip — single-container deployment for Railway.
#
# Design (per https://docs.paperclip.ing):
#   - Node.js 22+ runtime
#   - Embedded PostgreSQL (data persisted to a /data volume)
#   - Single port exposed (Railway injects PORT)
#
# This Dockerfile builds Paperclip from the upstream source repo.
# If the upstream build process changes, see docs/BOOTSTRAP_DOCKERFILE.md
# for the fallback (copy the verified Dockerfile from the reference
# Railway template).

ARG PAPERCLIP_REF=main

# ---- 1. Fetch upstream source ----------------------------------
FROM node:22-bookworm AS source
RUN apt-get update \
 && apt-get install -y --no-install-recommends git ca-certificates \
 && rm -rf /var/lib/apt/lists/*
WORKDIR /src
ARG PAPERCLIP_REF
RUN git clone --depth=1 --branch "${PAPERCLIP_REF}" \
      https://github.com/paperclipai/paperclip.git .

# ---- 2. Build ---------------------------------------------------
FROM node:22-bookworm AS build
WORKDIR /app
COPY --from=source /src /app
# Prefer reproducible install when a lockfile exists, otherwise fall back.
RUN if [ -f package-lock.json ]; then npm ci; \
    elif [ -f pnpm-lock.yaml ]; then corepack enable && pnpm install --frozen-lockfile; \
    elif [ -f yarn.lock ]; then corepack enable && yarn install --frozen-lockfile; \
    else npm install; fi
# Build step is best-effort — some Paperclip versions are pure JS.
RUN npm run build --if-present

# ---- 3. Runtime -------------------------------------------------
FROM node:22-bookworm-slim AS runtime
RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      postgresql postgresql-contrib ca-certificates tini \
 && rm -rf /var/lib/apt/lists/*

ENV NODE_ENV=production \
    PORT=3000 \
    PGDATA=/data/pgdata \
    DATABASE_URL=postgres://paperclip:paperclip@localhost:5432/paperclip

WORKDIR /app
COPY --from=build /app /app
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh \
 && mkdir -p /data \
 && chown -R postgres:postgres /data

VOLUME ["/data"]
EXPOSE 3000

ENTRYPOINT ["/usr/bin/tini", "--", "/usr/local/bin/entrypoint.sh"]
