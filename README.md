# DevOps Task API

A small Node.js/Express REST API used throughout the 3-session **DevOps & CI/CD Hands-on Bootcamp**. The same application is deployed three times, each time in a more modern way:

| Session | How it is deployed | What students learn |
| --- | --- | --- |
| 1. The "old way" | Node.js installed on the server, run by **systemd**, exposed by **Nginx** | Linux services, reverse proxies, why manual deploys hurt |
| 2. Containers | **Docker** image + **Docker Compose**, still behind Nginx | Images, containers, volumes, health checks |
| 3. CI/CD | **GitHub Actions** tests, builds, publishes to **GHCR** and deploys over SSH | Pipelines, registries, secrets, immutable releases, rollback |

Nginx stays the public entry point in all three sessions (port 80 → `127.0.0.1:3000`). Only what sits behind it changes.

```text
                 ┌─────────────── Ubuntu server ───────────────┐
 browser ──:80──▶│ Nginx ──▶ 127.0.0.1:3000 ──▶ Session 1: node (systemd)
                 │                             Session 2/3: container (Compose)
                 └─────────────────────────────────────────────┘
 Session 3:  git push ─▶ GitHub Actions ─▶ test ─▶ build ─▶ ghcr.io ─▶ ssh deploy.sh
```

---

## The application

| Method and path | Returns |
| --- | --- |
| `GET /` | Welcome message and version |
| `GET /health` | `{"status":"ok"}` |
| `GET /version` | Version (commit SHA in CI builds), environment, hostname |
| `GET /tasks` | All tasks |
| `POST /tasks` | Creates a task from `{"title": "..."}` (201), or 400 without a title |

Unknown routes return a JSON `404`, and malformed JSON bodies return a JSON `400`. Tasks are stored as JSON in `DATA_DIR` (default `./data`).

| Variable | Default | Purpose |
| --- | --- | --- |
| `PORT` | `3000` | Listening port |
| `APP_ENV` | `development` | Shown by `/version` |
| `APP_VERSION` | `package.json` version | Set to the commit SHA by CI |
| `DATA_DIR` | `./data` | Where `tasks.json` is written |

### Run locally (any session, on your laptop)

Requires Node.js 22 or newer.

```bash
npm ci
npm test
npm start                     # http://localhost:3000
```

```bash
curl localhost:3000/health
curl -X POST localhost:3000/tasks -H 'Content-Type: application/json' -d '{"title":"Learn CI/CD"}'
curl localhost:3000/tasks
```

### Repository layout

```text
src/                           Application code
test/                          Tests (node --test)
deploy/systemd/taskapi.service systemd unit for the manual deployment      (Session 1)
deploy/nginx/taskapi.conf      Nginx reverse proxy, unchanged afterwards  (Session 1-3)
Dockerfile, .dockerignore      Image definition                           (Session 2)
compose.yaml                   Development Compose file, builds locally   (Session 2)
.github/workflows/cicd.yml     CI/CD: test → build/publish → deploy       (Session 3)
deploy/compose.yaml            Production Compose file, pulls by digest   (Session 3)
deploy/app.env.example         Template for /srv/taskapi/app.env          (Session 3)
deploy/deploy.sh               Run by the pipeline on the server          (Session 3)
deploy/rollback.sh             Manual emergency rollback                  (Session 3)
```

---

## Prerequisites for the server

- One **Ubuntu 22.04 or 24.04** VM with a public IP (any cloud provider), and SSH access as a sudo user.
- Firewall / security group open for **22 (SSH)** and **80 (HTTP)**. Port 3000 must **not** be open: the app only listens on localhost.
- Your fork or copy of this repository on GitHub. In the commands below, replace `<owner>` with your GitHub user or organisation and `SERVER` with the server's IP address.

---

## Session 1: The old way (systemd + Nginx)

Goal: run the app directly on the server as a Linux service, with Nginx in front.

### 1.1 Install Node.js 22 and Nginx

Ubuntu's own `nodejs` package is too old (v18), so install it from NodeSource:

```bash
sudo apt update && sudo apt install -y nginx git curl
curl -fsSL https://deb.nodesource.com/setup_22.x | sudo -E bash -
sudo apt install -y nodejs
node -v                        # v22.x
which node                     # /usr/bin/node  (the path used in the systemd unit)
```

### 1.2 Create a service user and install the code

```bash
sudo useradd --system --no-create-home --shell /usr/sbin/nologin taskapi
sudo git clone https://github.com/omaradam61/devops-task-api.git /opt/taskapi
cd /opt/taskapi
sudo npm ci --omit=dev
```

The code is owned by root and only readable by `taskapi`. The app can write only to its data directory, `/var/lib/taskapi`, which systemd creates (`StateDirectory=`).

### 1.3 Run it with systemd

```bash
sudo cp deploy/systemd/taskapi.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now taskapi
systemctl status taskapi
journalctl -u taskapi -f       # live logs (Ctrl+C to exit)
curl localhost:3000/health
```

### 1.4 Put Nginx in front

```bash
sudo cp deploy/nginx/taskapi.conf /etc/nginx/sites-available/taskapi
sudo ln -s /etc/nginx/sites-available/taskapi /etc/nginx/sites-enabled/taskapi
sudo rm /etc/nginx/sites-enabled/default    # required: both files claim default_server
sudo nginx -t && sudo systemctl reload nginx
```

From your laptop:

```bash
curl http://SERVER/health
curl http://SERVER/version     # "environment":"production"
```

### 1.5 Updating the app: the pain point

```bash
cd /opt/taskapi
sudo git pull
sudo npm ci --omit=dev
sudo systemctl restart taskapi
```

Discussion points for the class:
- Every server needs the right Node.js version installed by hand ("works on my machine").
- Each deploy is a manual SSH session. Nothing records which commit is running, and there are no tests before it goes live.
- Rolling back means `git checkout` of an older commit and hoping the dependencies still match.

Sessions 2 and 3 fix these problems one at a time.

---

## Session 2: Containerise the application

Goal: package the app *and its runtime* into one image, then run it with Docker Compose. Nginx does not change.

### 2.1 Walk through the Dockerfile

Key ideas in [Dockerfile](Dockerfile):
- `node:22-alpine`: the runtime ships with the app, so the server no longer needs Node.js.
- Manifests are copied before the source so the `npm ci` layer is cached.
- `npm ci --omit=dev`: production dependencies only.
- `USER node`: the container never runs as root.
- `ARG APP_VERSION`: CI writes the commit SHA into the image (Session 3).

[.dockerignore](.dockerignore) keeps `node_modules`, `.git`, local data and secrets out of the build context.

### 2.2 Build and run on your laptop first

```bash
docker build -t devops-task-api:local .
docker run --rm -p 3000:3000 devops-task-api:local
curl localhost:3000/version
```

Then with Compose, which adds a volume, a restart policy and a health check:

```bash
docker compose up -d --build --wait
docker compose ps              # STATUS shows "(healthy)"
docker compose logs -f app
docker compose exec app id     # uid=1000(node): not root
docker compose down            # keeps the 'taskapi_taskdata' volume
```

### 2.3 Install Docker on the server

```bash
curl -fsSL https://get.docker.com | sudo sh
sudo usermod -aG docker $USER
exit                           # log out and back in so the group change applies
docker run --rm hello-world
```

> Being in the `docker` group is equivalent to having root. Only trusted users belong there.

### 2.4 Switch the server from systemd to Compose

The systemd service and the container both want `127.0.0.1:3000`, so **stop the old service first**:

```bash
sudo systemctl disable --now taskapi
curl -s localhost:3000/health || echo "port 3000 is free"

git clone https://github.com/omaradam61/devops-task-api.git ~/devops-task-api
cd ~/devops-task-api
docker compose up -d --build --wait
curl http://localhost/version   # through Nginx: "environment":"compose"
```

Nginx keeps proxying to `127.0.0.1:3000`, so neither its configuration nor the public URL changes.

**Optional: move the Session 1 data into the volume.** Running the copy as the container's `node` user keeps the file writable:

```bash
docker compose exec -T app sh -c 'cat > /app/data/tasks.json' < /var/lib/taskapi/tasks.json
docker compose restart app && curl localhost/tasks
```

### 2.5 Things to show

```bash
docker compose ps                         # health status
docker volume ls                          # taskapi_taskdata survives "down"
docker compose down && docker compose up -d --wait && curl localhost/tasks   # data is still there
sudo reboot                               # restart: unless-stopped brings it back
```

What is still manual: building on the server, `git pull`, and knowing which version is running. Session 3 automates all of it.

---

## Session 3: Automate the deployment with GitHub Actions

Goal: every merge to `main` is tested, built once into an immutable image, published to GHCR, and deployed to the server by its exact digest, with automatic rollback.

### 3.1 How the pipeline works

[.github/workflows/cicd.yml](.github/workflows/cicd.yml) has three jobs:

| Job | Runs on | What it does |
| --- | --- | --- |
| **Test** | every push and PR | `npm ci` and `npm test` |
| **Build and publish image** | after Test passes | Builds the image with `APP_VERSION=<commit SHA>`. On pushes to `main` it also pushes to `ghcr.io/<owner>/devops-task-api` with the `sha-xxxxxxx` and `latest` tags, then smoke-tests the published image. PRs build but never push. |
| **Deploy to Ubuntu server** | `main` only | Uses SSH to run `/srv/taskapi/deploy.sh ghcr.io/...@sha256:<digest>`, then checks from the internet that `/version` returns this commit's SHA |

[deploy/deploy.sh](deploy/deploy.sh) on the server works in five steps:
1. It pulls the new image first; if the pull fails, nothing on the server changes.
2. It saves the current release in `.env.previous`.
3. It writes the new digest to `.env`.
4. It runs `docker compose up --wait`. If the container is not healthy within 60 seconds, the script restores the previous release and the job fails.
5. It verifies `/health` and `/version` through Nginx.

### 3.2 One-time server setup

If Session 2 ran on this server, stop the development stack first. The volume is kept, and because both Compose files use the project name `taskapi`, production reuses the same `taskapi_taskdata` volume and its data:

```bash
cd ~/devops-task-api && docker compose down
```

Create a dedicated `deploy` user and install the production files (run from a checkout of the repo on the server):

```bash
sudo adduser --disabled-password --gecos "" deploy
sudo usermod -aG docker deploy
sudo install -d -o deploy -g deploy -m 750 /srv/taskapi
sudo install -o deploy -g deploy -m 644 deploy/compose.yaml /srv/taskapi/compose.yaml
sudo install -o deploy -g deploy -m 755 deploy/deploy.sh deploy/rollback.sh /srv/taskapi/
sudo install -o deploy -g deploy -m 600 deploy/app.env.example /srv/taskapi/app.env
sudo -u deploy nano /srv/taskapi/app.env      # real settings and secrets live here, never in Git
```

> These files are copied **once**. If you later change `deploy/compose.yaml` or `deploy/deploy.sh` in Git, run the `install` commands again.

### 3.3 Create the deploy SSH key (on your laptop)

```bash
ssh-keygen -t ed25519 -f ~/.ssh/taskapi_deploy -N "" -C "github-actions-deploy"
cat ~/.ssh/taskapi_deploy.pub                 # copy this line
```

On the server, authorise that public key for the `deploy` user:

```bash
sudo install -d -o deploy -g deploy -m 700 /home/deploy/.ssh
echo "ssh-ed25519 AAAA...paste... github-actions-deploy" | sudo tee -a /home/deploy/.ssh/authorized_keys
sudo chown deploy:deploy /home/deploy/.ssh/authorized_keys
sudo chmod 600 /home/deploy/.ssh/authorized_keys
```

Test it from your laptop. This is exactly what the pipeline will do:

```bash
ssh -i ~/.ssh/taskapi_deploy deploy@SERVER docker ps
```

### 3.4 Add the GitHub secrets

In **GitHub → Settings → Secrets and variables → Actions → New repository secret**, or with the `gh` CLI:

```bash
gh secret set DEPLOY_HOST --body "SERVER"            # IP or DNS name
gh secret set DEPLOY_USER --body "deploy"
gh secret set DEPLOY_SSH_KEY < ~/.ssh/taskapi_deploy # the PRIVATE key
ssh-keyscan -H SERVER | gh secret set DEPLOY_KNOWN_HOSTS
```

> `DEPLOY_KNOWN_HOSTS` must be scanned with **the same value as `DEPLOY_HOST`**. If you scan the IP but connect by DNS name, or the reverse, SSH fails with `Host key verification failed`.

Optional (continuous **delivery** instead of continuous **deployment**): in **Settings → Environments → production**, add yourself as a required reviewer. Every deploy then waits for a click.

### 3.5 First pipeline run and the GHCR package visibility

Push to `main`, or start the workflow from **Actions → CI/CD → Run workflow**.

The first push creates the package `ghcr.io/<owner>/devops-task-api`, which is **private by default**. If it is private, the server cannot pull it, and the deploy job fails with `denied` / `could not pull`. Choose one fix:

- **Simplest for a workshop:** on GitHub, go to **your profile → Packages → devops-task-api → Package settings → Change visibility → Public**, then re-run the failed job.
- **Keep it private:** create a classic personal access token with only `read:packages`, then on the server run `sudo -u deploy docker login ghcr.io -u <github-user>` once.

When the run is green:

```bash
curl http://SERVER/version
# {"version":"<full commit SHA>","environment":"production","hostname":"..."}
```

### 3.6 Live demo script

1. **A normal release.** Create a branch, change the welcome message in `src/app.js`, and open a pull request. Show that the **Test** and **Build** jobs run but nothing is pushed or deployed. Merge, watch all three jobs, then `curl http://SERVER/` shows the new message and `/version` shows the new SHA.
2. **Tests block bad code.** Change `/health` to return `res.status(500)` and push to a PR. **Test** fails, and nothing is built or deployed.
3. **Inspect what's live.** On the server, `cat /srv/taskapi/.env` (current digest) and `cat /srv/taskapi/.env.previous` (the one before). Compare with the digest in the workflow run summary.
4. **Emergency rollback.** Run `ssh deploy@SERVER /srv/taskapi/rollback.sh`; `/version` now shows the previous SHA. Run the latest workflow run's **Deploy** job again to roll forward.
5. **The preferred rollback.** Run `git revert <bad commit> && git push`. The pipeline ships the fix, and history shows what happened.
6. **Secret hygiene.** Show that secret values are masked as `***` in the logs and that the private key is deleted at the end of the job.

### 3.7 Operations reference

**What is live.** `curl http://SERVER/version` returns the commit SHA. On the server, `/srv/taskapi/.env` holds the current digest and `.env.previous` the one before.

**Rolling back.**
1. Preferred: `git revert <bad commit>` and push; the pipeline ships the fix.
2. Emergency: `ssh deploy@SERVER /srv/taskapi/rollback.sh`, or re-run the **Deploy** job of an older successful workflow run.

**Where secrets live** (names only, never values):

| Secret | Location |
| --- | --- |
| `DEPLOY_HOST`, `DEPLOY_USER`, `DEPLOY_SSH_KEY`, `DEPLOY_KNOWN_HOSTS` | GitHub → Settings → Secrets and variables → Actions |
| GHCR push credential | Automatic `GITHUB_TOKEN` (nothing stored) |
| App settings and secrets | `/srv/taskapi/app.env` on the server (mode 600) |

---

## Troubleshooting

| Symptom | Likely cause | Fix |
| --- | --- | --- |
| `nginx -t`: *a duplicate default server* | Ubuntu's `default` site is still enabled | `sudo rm /etc/nginx/sites-enabled/default` |
| `502 Bad Gateway` from Nginx | Nothing is listening on `127.0.0.1:3000` | `systemctl status taskapi` (S1) or `docker compose ps` (S2/3) |
| systemd: `status=203/EXEC` | Node.js is not at `/usr/bin/node` | Install from NodeSource, or fix `ExecStart` with the output of `which node` |
| Compose: *port is already allocated* | The Session 1 systemd service still owns port 3000 | `sudo systemctl disable --now taskapi` |
| `permission denied ... docker.sock` | User is not in the `docker` group, or has not logged in again | `sudo usermod -aG docker $USER`, then log out and back in |
| Deploy job: `Permission denied (publickey)` | Public key missing or wrong permissions on the server | Check `/home/deploy/.ssh` (700) and `authorized_keys` (600), owned by `deploy` |
| Deploy job: `Host key verification failed` | `DEPLOY_KNOWN_HOSTS` does not match `DEPLOY_HOST` | Re-run `ssh-keyscan -H <exact DEPLOY_HOST>` |
| Deploy job: `denied` / `could not pull` | GHCR package is private | Make it public or `docker login ghcr.io` on the server (3.5) |
| Build job: `denied: installation not allowed` when pushing | Package already exists and is not linked to this repo | Package settings → **Manage Actions access** → add the repo with *Write* |
| Verify step: `curl` times out | Port 80 is closed in the cloud firewall | Open port 80 in the security group, and in `ufw` if it is enabled |
| `/version` shows the old SHA | Deploy rolled back because the new container was unhealthy | Read the deploy job log; it prints the last 40 container log lines |
