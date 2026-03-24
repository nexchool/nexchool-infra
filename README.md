# school-erp-infra

**Infrastructure only** — Docker Compose, nginx, env files, scripts.  
Default layout: this folder lives **inside** the monorepo (e.g. `school-ERP/school-erp-infra/`).  
`SERVER_CONTEXT` / `SCHOOL_ADMIN_CONTEXT` / `SUPER_ADMIN_CONTEXT` are **relative to `docker/`** (same as Compose), e.g. `../../server`.

## Layout

```text
school-ERP/
├── school-erp-infra/     ← this repo
│   ├── docker/
│   │   ├── docker-compose.local.yml
│   │   ├── docker-compose.staging.yml
│   │   └── docker-compose.prod.yml
│   ├── nginx/
│   ├── env/
│   └── scripts/
├── server/
├── admin-web/
├── panel/
└── client/
```

Default contexts: `**../../server**`, `**../../admin-web**`, `**../../panel**` (from `docker/` up to monorepo root).

## AWS deployment

For **EC2 + Docker Compose + ECR + RDS + S3** (staging + prod) and CI/CD, use:

- `aws/AWS_DEPLOYMENT_GUIDE.md`
- `aws/terraform/*`
- `aws/ec2/nginx.conf` (reference; production `nginx.conf` is rendered from `aws/terraform/templates/nginx.conf.tpl`)

If apps live elsewhere, set paths **relative to `school-erp-infra/docker/`**, for example sibling repos:

```env
SERVER_CONTEXT=../../../other-root/server
```

## Environment files & GitHub

| File | Commit to Git? |
|------|----------------|
| **`env/.env.*`** (real files, e.g. `.env.local`, `.env.staging`, `.env.prod`) | **No** — passwords, JWT secrets, DB URLs. **`.gitignore`** ignores `env/.env*` and un-ignores only **`env/.env.*.example`**. |
| **`env/.env.*.example`** | **Yes** — templates with `CHANGEME` / safe dev defaults so others know which variables exist. |

**First-time setup**

```bash
cp env/.env.local.example env/.env.local
# edit .env.local if needed
```

Same idea for staging/prod on a server: copy the matching `.example` → real file and fill secrets there (or use your host’s secret manager and never put prod secrets in Git).

**Keep the three files in sync:** `env/.env.local`, `env/.env.staging`, and `env/.env.prod` should expose the **same variable names** (Compose loads the matching file per stack). If you add a key to one, add it to the others and to all three `*.example` templates — local-only keys (e.g. `POSTGRES_HOST_PORT`, `ADMIN_WEB_HOST_PORT`) can stay only in `.env.local*`.

**If you already committed real `.env.*` files**, remove them from Git history tracking (file can stay on disk):

```bash
git rm --cached env/.env.local env/.env.staging env/.env.prod  # or any tracked env/.env.*
git commit -m "Stop tracking env secrets; use .example templates"
```

Then rotate any secrets that were ever pushed (passwords, `JWT_SECRET_KEY`, etc.) — assume they are compromised.

### Merging old `server/` / app `.env` files

App repos (**`server`**, **`admin-web`**, **`panel`**, **`client`**) use **`.env*`** in their **`.gitignore`** with exceptions only for **`.env.example`** and **`.env.*.example`** — do not commit `.env.local` or `.env.production`.

If you previously used **`server/.env`**, **`admin-web/.env`**, **`panel/.env`**, **`client/.env`**:

1. **Docker workflow:** Put all **API-related** variables in **`school-erp-infra/env/.env.local`** (the `api` service loads that file). We merged the usual Flask keys there (`SMTP_*`, `CLOUDINARY_*`, JWT expiry, etc.); **re-paste** any secrets (email password, Cloudinary secret) from your old `server/.env` into `.env.local` — they are **not** committed.
2. **Next apps in Docker** do not need their own `.env` — Compose sets `NEXT_PUBLIC_*` from the same infra env.
3. **Expo `client/`** still uses **`client/.env`** locally (not Docker). Copy values from the old file into a new `client/.env` from **`client/.env.example`**, or keep one gitignored `client/.env` on your machine only.

After copying anything you still need, you can remove the duplicate root `.env` files so secrets do not live in four places.

## Environments


| Env         | Compose file                 | Env file           | Typical HTTP port |
| ----------- | ---------------------------- | ------------------ | ----------------- |
| **local**   | `docker-compose.local.yml`   | `env/.env.local`   | 8080 (default; avoids host port 80) |
| **staging** | `docker-compose.staging.yml` | `env/.env.staging` | 8080 (default)    |
| **prod**    | `docker-compose.prod.yml`    | `env/.env.prod`    | 8080 in template; set **80** on EC2 if you want public :80 |


Staging uses Compose project name `**school-erp-staging`** and a separate Postgres volume + DB name so it does not collide with prod on the same machine.

### How configs differ by environment

| | **local** | **staging** | **prod** |
|---|-----------|-------------|----------|
| **Compose file** | `docker-compose.local.yml` | `docker-compose.staging.yml` | `docker-compose.prod.yml` |
| **Env file** | `env/.env.local` | `env/.env.staging` | `env/.env.prod` |
| **Next / API** | Dev images (`Dockerfile.dev`, Next `development`) | Production Dockerfile targets | Production Dockerfile targets |
| **Nginx published** | `${HTTP_PORT}:8080` | `${HTTP_PORT}:8080` | `${HTTP_PORT}:8080` |
| **Next on host (3000/3001)** | Yes — optional (`ADMIN_WEB_HOST_PORT`, `PANEL_HOST_PORT` in `.env.local`) | **No** — use `http://host:$HTTP_PORT/` and `/panel/` | **No** — use nginx or external LB |
| **`nginx/nginx.conf`** | **One file:** `listen 8080;` in-container — **must** match compose `…:8080` | | |

**Port contract (do not split this across edits):** `nginx/nginx.conf` → **`listen 8080;`**. All three compose files → **`"${HTTP_PORT:-8080}:8080"`** for the nginx service. `HTTP_PORT` is only the **host** port (browser / CORS); nginx always listens on **8080 inside the container**. Example: `HTTP_PORT=80` → host **80** → container **8080**.

## Commands

```bash
chmod +x scripts/*.sh

./scripts/dev.sh           # local, foreground
./scripts/staging.sh       # staging, detached
./scripts/prod.sh          # production, detached

./scripts/deploy.sh staging   # git pull apps + staging up --build
./scripts/deploy.sh prod      # git pull apps + prod up --build
```

Or: `make dev` | `make staging` | `make prod` | `make deploy-staging` | `make deploy-prod`.

## Services

Internal Docker DNS: `**postgres**`, `**redis**`, `**api**`, `**admin-web**`, `**panel**`, `**nginx**`.

**Staging / prod:** only **nginx** publishes **`${HTTP_PORT}:8080`**.  
**Local:** same nginx mapping, plus optional **3000** / **3001** for Next (see `env/.env.local`).

## Nginx (recommended local URL)

With `HTTP_PORT=8080`:

- **http://localhost:8080/** — school admin (Next)
- **http://localhost:8080/panel/** — super admin (Next; `basePath: "/panel"`)
- **http://localhost:8080/api/...** — API

`admin-web` and `panel` also publish **direct** dev ports (see `env/.env.local`):

- **http://localhost:3000/** — school admin (bypass nginx)
- **http://localhost:3001/panel/** — super admin (path **`/panel`** required)

Inside Docker, both Next apps listen on **3000**; only **nginx** had a host port before — that’s why `:3000` / `:3001` looked “dead” until those mappings were added to `docker-compose.local.yml`.

**Note:** If you open **:3000** or **:3001** directly, relative `/api/*` would hit **Next** (HTML 404), not Flask. Compose sets **`NEXT_PUBLIC_GATEWAY_ORIGIN=http://localhost:${HTTP_PORT}`** on both Next services so the client calls Flask via nginx. **`CORS_ORIGINS`** in `env/.env.local` must include those origins (already includes `3000`/`3001`). Rebuild or recreate containers after changing env.

## Logs

```bash
docker compose -f docker/docker-compose.local.yml --env-file env/.env.local logs -f api
```

Docker logging: json-file, 10MB × 3 rotations per service.