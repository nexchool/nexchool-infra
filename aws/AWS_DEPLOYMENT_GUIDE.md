# AWS deployment (EC2 + Docker Compose, **production**)

Cost-focused stack (~\$20–35/month before domain):

- **1× EC2** (`t4g.micro` ARM or `t3.micro` x86) — Docker + Compose
- **ECR** — images for `api`, `admin-web`, `panel` (unchanged build/push flow)
- **RDS PostgreSQL** `db.t4g.micro`, single-AZ
- **S3** — uploads (EC2 instance profile, **no access keys**)
- **Elastic IP** — stable public IP for DNS / `BACKEND_URL`
- **No** ECS, **no** ALB, **no** NAT Gateway

Runtime layout on the server:

```text
/home/ec2-user/app/
  docker-compose.yml   # from Terraform template
  nginx.conf           # from Terraform template (API upstream port = `api_port`)
  .env                 # from Terraform `env.tpl` (secrets + api + Next.js)
```

Templates live in `aws/terraform/templates/`; reference copies under `aws/ec2/` (ECR placeholders). Key list for `.env`: `aws/terraform/app.env.example`.

## 1) One-time AWS setup

1. IAM admin user (avoid long-term root use).
2. Install **Terraform ≥ 1.5** and **AWS CLI v2** locally.
3. `aws configure`
4. Create an **EC2 Key Pair** (e.g. `school-erp-prod`) and download the `.pem`.
5. Pick **region** (examples: `ap-south-1`).

## 2) Terraform (single production stack)

From `school-erp-infra/aws/terraform`:

```bash
terraform init
cp prod.tfvars.example prod.tfvars   # edit secrets
terraform apply -var-file=prod.tfvars
terraform output
```

Use one state file / one workspace for this production environment.

## 3) Configure `prod.tfvars`

Important keys:

| Key | Notes |
|-----|--------|
| `environment` | Use `prod` |
| `ec2_key_name` | **Name** of an existing EC2 key pair in **the same region** as `aws_region` (not the `.pem` filename). If Terraform fails with `InvalidKeyPair.NotFound`, create the pair in the console (**EC2 → Key pairs → Create**) or CLI, or set `ec2_key_name` to a pair that already exists. |
| `ssh_cidr` | **Your** public IP `/32` for SSH (e.g. `203.0.113.10/32`) |
| `cors_origins` | After apply, include `http://<EIP>` and your HTTPS origins |
| `app_public_base_url` | Optional. Empty = `http://<EIP>` for `BACKEND_URL` and default `NEXT_PUBLIC_API_URL` in `.env`. Set `https://…` when you have a stable public origin. |
| `next_public_api_url` | Optional override for `NEXT_PUBLIC_*` in `.env` only (see CI note below). |
| `db_*`, `secret_key`, `jwt_secret_key` | Strong secrets |
| `db_password` | **RDS rule:** 8–128 chars, printable ASCII, **must not** contain `/`, `@`, `"`, or **space** (common failure: passwords with `@` or base64 `/`). `terraform plan` validates this. |

Save outputs:

- `ec2_elastic_ip` → GitHub secret `EC2_HOST_PROD`, DNS **A** record
- `*_ecr_repository_url` → `ECR_REPO_*` secrets (full repo URLs)
- `ecr_registry_url` → optional; workflows derive registry from `ECR_REPO`

### First boot

`user_data` installs Docker, writes `/home/ec2-user/app/*`, logs in to ECR, runs `docker compose up -d`.

To **change** env vars or secrets, edit `prod.tfvars` (or `-var` / workspace) and **replace** the EC2 instance so `user_data` runs again (Terraform `user_data` changes typically force replacement). Then CI `docker compose pull && up -d` picks up images; `.env` is only rewritten on new instance bootstrap — avoid hand-editing `.env` on the server for reproducibility.

## 4) CI/CD (GitHub Actions)

Workflows: `ec2-deploy.yml` in `server`, `admin-web`, `panel`.

| Trigger | Target |
|---------|--------|
| Push to `main` | **Production** |
| `workflow_dispatch` | **Production** (manual redeploy) |

### Required secrets (each app repo)

Workflows use the `*_PROD` names below (single production environment).

| Secret | Purpose |
|--------|---------|
| `AWS_ROLE_TO_ASSUME_PROD` | OIDC role for ECR push |
| `ECR_REPO_API_PROD` | Full ECR API image URL (no tag) — **server** repo |
| `ECR_REPO_ADMIN_WEB_PROD` | Full ECR admin-web URL — **admin-web** repo |
| `ECR_REPO_PANEL_PROD` | Full ECR panel URL — **panel** repo |
| `EC2_HOST_PROD` | Elastic IP or DNS for SSH |
| `EC2_SSH_PRIVATE_KEY` | PEM contents for `ec2-user` |
| `NEXT_PUBLIC_API_URL_PROD` | **admin-web + panel only** — passed as Docker `build-arg` at image build time |

**Next.js note:** `NEXT_PUBLIC_*` is embedded at **build** time. Runtime `.env` on EC2 keeps server-side Node env aligned and documents the intended URL; GitHub Actions must still use a `NEXT_PUBLIC_API_URL_PROD` secret that matches `app_public_base_url` / `next_public_api_url` (or the EIP URL) so browser bundles call the correct API.

Deploy step: SSH → `aws ecr get-login-password | sudo docker login` → `sudo docker compose pull && up -d` → `sudo docker system prune -af --volumes || true` (frees old images/layers; failures ignored).

### SSH from GitHub-hosted runners

GitHub’s outbound IPs are **not** fixed. If deploy fails with “connection refused” on port 22:

- Temporarily widen `ssh_cidr` (e.g. `0.0.0.0/0`) and rely on key-only SSH, **or**
- Use a **self-hosted runner** in your network, **or**
- Switch deploy to **SSM Run Command** (add `AmazonSSMManagedInstanceCore` to the EC2 role and no inbound 22 from the internet).

## 5) Environment variables on EC2

Single file `/home/ec2-user/app/.env`, generated from Terraform (`templates/env.tpl`), loaded by **api**, **celery-worker**, **celery-beat**, **admin-web**, and **panel** via `env_file: .env`.

Includes Flask (`DATABASE_URL`, `SECRET_KEY`, `JWT_*`, `DEFAULT_USER_ROLE`, mail, session, `CORS_ORIGINS`, `BACKEND_URL`, Gunicorn worker/thread envs), AWS (`AWS_REGION`, `S3_BUCKET_NAME`), Redis/Celery URLs, and Next-oriented keys (`NODE_ENV`, `NEXT_PUBLIC_API_URL`, optional `NEXT_PUBLIC_GATEWAY_ORIGIN`). See `aws/terraform/app.env.example` for the full key list.

S3 access uses the **instance IAM role** (no `AWS_ACCESS_KEY_ID` in `.env`).

## 6) HTTPS / domain (optional)

1. Point DNS **A** record at `ec2_elastic_ip`.
2. Set `app_public_base_url` (and CI `NEXT_PUBLIC_API_URL_PROD`) to `https://…`; update `cors_origins` accordingly. Replace the instance or re-bootstrap so `.env` and templated `nginx.conf` refresh.
3. On the server, install **Certbot** and extend the nginx config with `listen 443 ssl` and certificate paths (comment block in `aws/ec2/nginx.conf`; production nginx on EC2 is generated from `templates/nginx.conf.tpl`).

## 7) Low-RAM EC2 hardening (t3/t4g.micro)

The generated Compose file includes:

- **Memory + CPU** limits (`deploy.resources.limits`) — Compose **v2.20+** (bootstrap installs **2.29.7**)
- **`ulimits.nofile`** on **api** and **nginx**
- **`stop_grace_period: 30s`** on all services
- **json-file** log rotation (`10m` × 3)
- **Redis** `maxmemory` + **1G swap** in `user_data`
- **Gunicorn** 1×2 threads (env + `gunicorn_conf.py`)
- **Next.js** `NODE_OPTIONS=--max-old-space-size=128` on admin-web + panel
- **API healthcheck** on `GET /api/health` (requires **`curl`** in the API image — see `server/Dockerfile`)
- **Celery** — `celery-worker` and `celery-beat` use the **same API image** with an overridden entrypoint (email tasks, scheduled jobs). Without `celery-worker`, async email queues are never consumed.
- **ARM EC2 (`t4g`)** — Do **not** pin `platform: linux/amd64` on app images in Compose. ECR images are **multi-arch**; forcing amd64 on Graviton causes **`exec format error`** in the container. The generated Compose omits `platform` so Docker uses the native **arm64** layer.

## 8) Rough monthly cost (production)

| Item | Approx. |
|------|---------|
| EC2 `t4g.micro` | ~\$6–10 |
| EBS ~30 GB gp3 | ~\$2–3 |
| Elastic IP (attached) | \$0 |
| RDS `db.t4g.micro` | ~\$12–18 |
| S3 | ~\$1–3 |
| **Total** | **~\$22–35** |

## 9) Operations

- **Logs:** `sudo docker compose -f /home/ec2-user/app/docker-compose.yml logs -f api` — for async email / Celery task errors also: `logs -f celery-worker` (and `celery-beat` for scheduler).
- **Migrations:** run against RDS from a bastion or temporarily allow your IP on RDS SG (tighten after).

## Basic Server Monitoring (EC2)

SSH to the instance, then use:

| Command | What it shows |
|--------|----------------|
| `htop` | CPU and process usage (install with `sudo dnf install -y htop` on Amazon Linux if missing) |
| `free -h` | Memory and swap usage |
| `docker stats` | Live CPU/memory per container |
| `df -h` | Disk space (root volume and mounts) |

## 10) S3 storage (backend)

Student documents use S3 via IAM role. DB columns still named `cloudinary_*` but store S3 URL/key — no app-code change required for this infra refactor.
