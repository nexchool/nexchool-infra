# school-erp-infra

Docker Compose, nginx, and env files for **local development** and **production** (build or ECR).

## Layout

```text
school-erp-infra/
  docker/
    docker-compose.local.yml   # make dev — hot-reload, Postgres, build contexts
    docker-compose.prod.yml    # make prod — production-like build + Postgres
    docker-compose.ecr.yml     # ECR images (AWS) — make deploy-ecr / start-prod.sh
  env/
    .env.local.example         # → copy to .env.local
    .env.prod.example          # → copy to .env.prod
  nginx/
    nginx.local.conf           # local routing (default: admin; optional: panel.localhost)
    nginx.prod.conf            # production domain routing (nexchool.in / app.* / panel.* / api.*)
  scripts/
    dev.sh                     # local stack
    prod.sh                    # build prod stack
    deploy.sh                  # [prod|ecr] — prod: git pull + up --build; ecr: pull + up
    start-prod.sh              # ECR up -d (same as deploy ecr without pull)
    deploy-ecr.sh              # thin wrapper → deploy.sh ecr
  Makefile
```

## First-time env

```bash
cd school-erp-infra
cp env/.env.local.example env/.env.local
cp env/.env.prod.example env/.env.prod
# edit secrets in both
```

## Makefile commands

| Command | What it runs |
|--------|----------------|
| `make dev` | `./scripts/dev.sh` → `docker-compose.local.yml` + `env/.env.local` |
| `make prod` | `./scripts/prod.sh` → `docker-compose.prod.yml` + `env/.env.prod` (build + up) |
| `make deploy-prod` | Git pull on server/admin/panel repos, then prod compose up --build |
| `make deploy-ecr` | Pull ECR images + `up -d` (no app git pull) |
| `make clean` | Tear down local stack + remove Next `node_modules` volumes |
| `make clean-dev` | `clean` then `dev` |

From the **monorepo root**: `make infra-dev` (see root `Makefile`).

## Production on EC2

Copy this whole folder to `/home/ec2-user/app` (or keep a git clone and `cd school-erp-infra`). Ensure `env/.env.prod` exists with `ECR_*` and secrets. Then:

```bash
docker compose -f docker/docker-compose.ecr.yml --env-file env/.env.prod up -d
# updates:
docker compose -f docker/docker-compose.ecr.yml --env-file env/.env.prod pull
docker compose -f docker/docker-compose.ecr.yml --env-file env/.env.prod up -d
```

## Nginx

Config lives in **`nginx/`** and is mounted by compose:

- **Local**: `nginx/nginx.local.conf`
- **Prod/ECR**: `nginx/nginx.prod.conf` (includes marketing site `nexchool.in` + `www.nexchool.in`)

## CI

Next.js `NEXT_PUBLIC_*` are baked at image build. Keep `env/.env.prod` aligned with GitHub Actions secrets for admin-web and panel.
