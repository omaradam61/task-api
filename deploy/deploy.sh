#!/usr/bin/env bash
# deploy.sh - deploy one exact, immutable image to this server
# Usage: deploy.sh ghcr.io/<owner>/<repo>@sha256:<digest>
set -euo pipefail

APP_DIR=/srv/taskapi
NEW_IMAGE="${1:-}"

# Accept only a GHCR image pinned by digest
if [[ ! "$NEW_IMAGE" =~ ^ghcr\.io/[a-z0-9._/-]+@sha256:[a-f0-9]{64}$ ]]; then
  echo "ERROR: expected ghcr.io/<owner>/<repo>@sha256:<digest>, got '$NEW_IMAGE'" >&2
  exit 2
fi

cd "$APP_DIR"

# 1. Remember the release that is running now, for rollback
if [[ -f .env ]]; then cp .env .env.previous; fi

# 2. Point Compose at the new image
echo "APP_IMAGE=$NEW_IMAGE" > .env

# 3. Pull, start, and wait until Docker reports the container healthy
docker compose pull app
if docker compose up -d --wait --wait-timeout 60; then
  echo "Container is healthy."
else
  echo "ERROR: new release did not become healthy. Last log lines:" >&2
  docker compose logs --tail 40 app >&2 || true
  if [[ -f .env.previous ]]; then
    echo "Rolling back to $(cut -d= -f2- .env.previous)" >&2
    cp .env.previous .env
    docker compose up -d --wait --wait-timeout 60 || true
  fi
  exit 1
fi

# 4. Verify through Nginx: the same path users take
curl -fsS http://127.0.0.1/health && echo
curl -fsS http://127.0.0.1/version && echo

# 5. Remove unused images to keep the disk clean
docker image prune -f > /dev/null
echo "Deployed $NEW_IMAGE"
