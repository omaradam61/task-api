#!/usr/bin/env bash
# rollback.sh - return to the release that ran before the last deploy
set -euo pipefail
cd /srv/taskapi

if [[ ! -f .env.previous ]]; then
  echo "No previous release recorded." >&2
  exit 1
fi

cp .env .env.rolled-back
cp .env.previous .env
docker compose up -d --wait --wait-timeout 60   # pulls the old digest again if it was pruned
echo "Rolled back to $(cut -d= -f2- .env)"
curl -fsS http://127.0.0.1/version && echo
