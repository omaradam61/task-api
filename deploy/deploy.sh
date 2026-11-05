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

# 1. Pull first, BEFORE touching any state. If the pull fails (private
#    package, no registry login, typo) nothing on the server has changed.
if ! docker pull "$NEW_IMAGE"; then
  echo "ERROR: could not pull $NEW_IMAGE." >&2
  echo "Is the GHCR package public, or is this server logged in to ghcr.io?" >&2
  exit 1
fi

# 2. Remember the release that is running now, for rollback.
#    Re-deploying the same image must not overwrite the rollback target.
if [[ -f .env ]] && [[ "$(cat .env)" != "APP_IMAGE=$NEW_IMAGE" ]]; then
  cp .env .env.previous
fi

# 3. Point Compose at the new image
echo "APP_IMAGE=$NEW_IMAGE" > .env

# 4. Start it and wait until Docker reports the container healthy
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

# 5. Verify through Nginx: the same path users take
curl -fsS --retry 5 --retry-delay 2 --retry-all-errors http://127.0.0.1/health && echo
curl -fsS http://127.0.0.1/version && echo

# 6. Remove unused images to keep the disk clean
#    (rollback.sh re-pulls the previous digest if it was removed)
docker image prune -f > /dev/null
echo "Deployed $NEW_IMAGE"
