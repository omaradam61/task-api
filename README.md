# DevOps Task API

A small Node.js/Express REST API used throughout the 3-session **DevOps & CI/CD Hands-on Bootcamp**: deployed manually with systemd and Nginx (Session 1), containerised with Docker Compose (Session 2), and shipped automatically by GitHub Actions to an Ubuntu server (Session 3).

## Endpoints

| Method and path | Returns |
| --- | --- |
| `GET /` | Welcome message and version |
| `GET /health` | `{"status":"ok"}` |
| `GET /version` | Version (commit SHA in CI builds), environment, hostname |
| `GET /tasks` | All tasks |
| `POST /tasks` | Creates a task from `{"title": "..."}` (201), or 400 without a title |

Tasks are stored as JSON in `DATA_DIR` (default `./data`).

## Run locally

```bash
npm ci
npm test
npm start                     # http://localhost:3000
```

| Variable | Default | Purpose |
| --- | --- | --- |
| `PORT` | `3000` | Listening port |
| `APP_ENV` | `development` | Shown by `/version` |
| `APP_VERSION` | `package.json` version | Set to the commit SHA by CI |
| `DATA_DIR` | `./data` | Where `tasks.json` is written |

## Run with Docker

```bash
docker compose up -d --build
curl http://localhost:3000/health
docker compose down           # keeps the 'taskapi_taskdata' volume
```

## Repository layout

```text
.github/workflows/cicd.yml     CI/CD: test → build/publish to GHCR → deploy → verify
deploy/nginx/taskapi.conf      Nginx reverse proxy (Session 1, unchanged afterwards)
deploy/systemd/taskapi.service systemd unit for the manual deployment (Session 1)
deploy/compose.yaml            Production Compose file, pulls by digest (Session 3)
deploy/app.env.example         Template for /srv/taskapi/app.env on the server
deploy/deploy.sh               Run by the pipeline on the server; auto-rollback on failure
deploy/rollback.sh             Manual emergency rollback
src/                           Application code
test/                          Tests (node --test)
Dockerfile, .dockerignore      Image definition
compose.yaml                   Development Compose file, builds locally (Session 2)
```

## Operations

**How a release happens.** Merge a pull request into `main`. The `CI/CD` workflow runs the tests, builds the image, pushes it to `ghcr.io/<owner>/devops-task-api`, smoke-tests it, then SSHes to the server as `deploy` and runs `/srv/taskapi/deploy.sh <image@sha256:digest>`. The script pulls that exact digest, waits for the health check and verifies through Nginx; if the new container is unhealthy it restores the previous release and fails the job.

**What is live.** `curl http://SERVER/version` returns the commit SHA. On the server, `/srv/taskapi/.env` holds the current digest and `.env.previous` the one before.

**Rolling back.**
1. Preferred: `git revert <bad commit>` and push; the pipeline ships the fix.
2. Emergency: `ssh deploy@SERVER /srv/taskapi/rollback.sh`, or re-run an older successful workflow run.

**Where secrets live** (names only, never values):

| Secret | Location |
| --- | --- |
| `DEPLOY_HOST`, `DEPLOY_USER`, `DEPLOY_SSH_KEY`, `DEPLOY_KNOWN_HOSTS` | GitHub → Settings → Secrets and variables → Actions |
| GHCR push credential | Automatic `GITHUB_TOKEN` (nothing stored) |
| App settings and secrets | `/srv/taskapi/app.env` on the server (mode 600) |

## One-time server setup (Session 3)

```bash
sudo adduser --disabled-password --gecos "" deploy
sudo usermod -aG docker deploy
sudo install -d -o deploy -g deploy -m 750 /srv/taskapi
sudo install -o deploy -g deploy -m 644 deploy/compose.yaml /srv/taskapi/compose.yaml
sudo install -o deploy -g deploy -m 755 deploy/deploy.sh deploy/rollback.sh /srv/taskapi/
sudo install -o deploy -g deploy -m 600 deploy/app.env.example /srv/taskapi/app.env
# then add the GitHub Actions public key to /home/deploy/.ssh/authorized_keys
```
