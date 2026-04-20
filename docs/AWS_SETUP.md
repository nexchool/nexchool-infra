# AWS Infrastructure Setup Guide

Complete record of the Nexchool production infrastructure setup on AWS.

---

## What's Running

| Service | Where |
|---------|-------|
| Flask API + Gunicorn | EC2 (Docker) |
| Celery Worker + Beat | EC2 (Docker) |
| Redis | EC2 (Docker) |
| admin-web (Next.js) | EC2 (Docker) |
| panel / super-admin (Next.js) | EC2 (Docker) |
| Nginx (reverse proxy + SSL) | EC2 (Docker) |
| PostgreSQL | RDS (managed) |
| Docker images | ECR (3 repos) |
| landing-page | Vercel (separate) |
| mobile client | Play Store (separate) |

**Region:** `ap-south-1` (Mumbai)
**AWS Account ID:** `774493573217`

---

## Domains

| Domain | Points to |
|--------|-----------|
| `app.nexchool.in` | EC2 Elastic IP |
| `panel.nexchool.in` | EC2 Elastic IP |
| `api.nexchool.in` | EC2 Elastic IP |

DNS is managed on **spaceship.com** — all 3 are A records pointing to the EC2 Elastic IP.

---

## EC2 Instance

| Property | Value |
|----------|-------|
| Name | `nexchool-prod` |
| Type | `t3.small` (2 vCPU, 2GB RAM) |
| AMI | Amazon Linux 2023 |
| Key pair | `nexchool-prod` → `~/.ssh/nexchool-prod.pem` |
| Security group | `nexchool-prod-sg` |
| Elastic IP | attached (permanent, won't change on restart) |
| IAM profile | `nexchool-ec2-ecr-role` (ECR pull access) |
| Swap | 1GB at `/swapfile` |

**SSH:**
```bash
ssh -i ~/.ssh/nexchool-prod.pem ec2-user@13.206.92.120
```

**Security group inbound rules:**

| Port | Source | Why |
|------|--------|-----|
| 22 | My IP | SSH (update when your IP changes) |
| 80 | 0.0.0.0/0 | HTTP + Certbot ACME |
| 443 | 0.0.0.0/0 | HTTPS production traffic |

> **Gotcha:** If SSH times out, your home IP changed. Go to EC2 → Security Groups → `nexchool-prod-sg` → Edit inbound rules → set SSH source to "My IP" and save.

---

## RDS (PostgreSQL)

| Property | Value |
|----------|-------|
| Identifier | `nexchool-prod` |
| Engine | PostgreSQL 16 |
| Instance | `db.t3.micro` |
| Endpoint | `nexchool-prod-rds.cl22qys6w06n.ap-south-1.rds.amazonaws.com` |
| Port | `5432` |
| Database name | `postgres` |
| Username | `postgres` |
| Public access | No |
| Security group | `nexchool-rds-sg` |

**RDS security group inbound rule:**

| Port | Source | Why |
|------|--------|-----|
| 5432 | `nexchool-prod-sg` | Only EC2 can reach RDS |

---

## ECR Repositories

All in `ap-south-1`, private:

| Repository | URI | Built by |
|------------|-----|----------|
| `nexchool-server` | `774493573217.dkr.ecr.ap-south-1.amazonaws.com/nexchool-server` | `server` repo CI |
| `nexchool-school-admin-panel` | `774493573217.dkr.ecr.ap-south-1.amazonaws.com/nexchool-school-admin-panel` | `school-admin-panel` repo CI |
| `nexchool-super-admin-panel` | `774493573217.dkr.ecr.ap-south-1.amazonaws.com/nexchool-super-admin-panel` | `super-admin-panel` repo CI |

---

## IAM Setup

### EC2 Role — `nexchool-ec2-ecr-role`
- **Type:** EC2 instance profile
- **Policy:** `AmazonEC2ContainerRegistryReadOnly`
- **Purpose:** Allows EC2 to pull images from ECR without static keys

### GitHub Actions Role — `nexchool-github-actions-role`
- **Type:** Web identity (OIDC)
- **OIDC Provider:** `token.actions.githubusercontent.com`
- **Audience:** `sts.amazonaws.com`
- **Trust condition:** `repo:nexchool/*:ref:refs/heads/main`
- **Policy:** `AmazonEC2ContainerRegistryPowerUser`
- **Purpose:** Allows GitHub Actions to push images to ECR and SSH to EC2

**Role ARN:** `arn:aws:iam::774493573217:role/nexchool-github-actions-role`

---

## GitHub Secrets

Set in each repo under **Settings → Secrets and variables → Actions**.

### Secrets in ALL 3 repos

| Secret | Value |
|--------|-------|
| `AWS_ROLE_TO_ASSUME` | `arn:aws:iam::774493573217:role/nexchool-github-actions-role` |
| `EC2_HOST` | EC2 Elastic IP |
| `EC2_SSH_PRIVATE_KEY` | contents of `~/.ssh/nexchool-prod.pem` |

### `server` repo only

| Secret | Value |
|--------|-------|
| `ECR_REPO_SERVER` | `774493573217.dkr.ecr.ap-south-1.amazonaws.com/nexchool-server` |

### `school-admin-panel` repo

| Secret | Value |
|--------|-------|
| `ECR_REPO_ADMIN_WEB` | `774493573217.dkr.ecr.ap-south-1.amazonaws.com/nexchool-school-admin-panel` |
| `NEXT_PUBLIC_API_URL` | `https://api.nexchool.in` |
| `NEXT_PUBLIC_PANEL_URL` | `https://panel.nexchool.in` |
| `NEXT_PUBLIC_GATEWAY_ORIGIN` | `https://app.nexchool.in` |
| `NEXT_PUBLIC_FIREBASE_*` | Firebase project settings |

### `super-admin-panel` repo

| Secret | Value |
|--------|-------|
| `ECR_REPO_PANEL` | `774493573217.dkr.ecr.ap-south-1.amazonaws.com/nexchool-super-admin-panel` |
| `NEXT_PUBLIC_API_URL` | `https://api.nexchool.in` |
| `NEXT_PUBLIC_PANEL_URL` | `https://panel.nexchool.in` |
| `NEXT_PUBLIC_GATEWAY_ORIGIN` | `https://panel.nexchool.in` |

---

## CI/CD Flow

On every push to `main` in any of the 3 repos:

1. GitHub Actions authenticates to AWS via OIDC (no static keys)
2. Builds a `linux/amd64` Docker image
3. Pushes it to ECR with tags `:latest` and `:<git-sha>`
4. SSHs into EC2 and runs:
   ```bash
   docker compose -f docker-compose.prod.yml --env-file .env.prod pull <service>
   docker compose -f docker-compose.prod.yml --env-file .env.prod up -d --remove-orphans
   docker image prune -f
   ```

---

## EC2 File Layout

```
/home/ec2-user/
├── docker-compose.prod.yml   # from nexchool-infra/docker-compose.prod.yml
├── .env.prod                 # never committed, fill from env/.env.prod.example
├── nginx.conf                # from nexchool-infra/nginx/nginx.prod.conf
├── certbot-webroot/          # ACME challenge directory (mkdir once)
└── /swapfile                 # 1GB swap (permanent via /etc/fstab)

/etc/letsencrypt/live/app.nexchool.in/
├── fullchain.pem             # mounted read-only into nginx container
└── privkey.pem
```

---

## EC2 Initial Setup Steps

### 1. Install Docker
```bash
sudo dnf update -y
sudo dnf install -y docker
sudo systemctl enable --now docker
sudo usermod -aG docker ec2-user
sudo mkdir -p /usr/local/lib/docker/cli-plugins
sudo curl -SL https://github.com/docker/compose/releases/latest/download/docker-compose-linux-x86_64 \
  -o /usr/local/lib/docker/cli-plugins/docker-compose
sudo chmod +x /usr/local/lib/docker/cli-plugins/docker-compose
sudo dnf install -y aws-cli
# log out and back in after this
```

### 2. Add Swap (important for memory stability)
```bash
sudo fallocate -l 1G /swapfile
sudo chmod 600 /swapfile
sudo mkswap /swapfile
sudo swapon /swapfile
echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab
```

### 3. Install Certbot
```bash
sudo dnf install -y python3-pip
sudo pip3 install certbot
```

### 4. Get SSL Certificate (run before starting Docker)
```bash
sudo certbot certonly --standalone \
  -d app.nexchool.in \
  -d panel.nexchool.in \
  -d api.nexchool.in \
  --agree-tos \
  --email hello@nexchool.in \
  --non-interactive
```

### 5. Place Config Files
```bash
# From local machine:
scp -i ~/.ssh/nexchool-prod.pem \
  path/to/nexchool-infra/docker-compose.prod.yml \
  ec2-user@13.206.92.120:~/docker-compose.prod.yml

scp -i ~/.ssh/nexchool-prod.pem \
  path/to/nexchool-infra/nginx/nginx.prod.conf \
  ec2-user@13.206.92.120:~/nginx.conf

# On EC2:
mkdir -p ~/certbot-webroot
nano ~/.env.prod   # fill in all values from env/.env.prod.example
```

### 6. Login to ECR and Start Stack
```bash
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
aws ecr get-login-password --region ap-south-1 \
  | sudo docker login --username AWS --password-stdin \
    "${AWS_ACCOUNT_ID}.dkr.ecr.ap-south-1.amazonaws.com"

sudo docker compose -f docker-compose.prod.yml --env-file .env.prod up -d
```

### 7. Seed Database (first time only)
```bash
sudo docker compose -f docker-compose.prod.yml --env-file .env.prod \
  exec api python -m scripts.seed_rbac

sudo docker compose -f docker-compose.prod.yml --env-file .env.prod \
  exec -it api python -m scripts.create_admin
```

### 8. SSL Auto-renewal (cron)
```bash
crontab -e
# Add this line:
0 3 * * * sudo certbot renew --webroot -w /home/ec2-user/certbot-webroot --quiet && sudo docker compose -f /home/ec2-user/docker-compose.prod.yml --env-file /home/ec2-user/.env.prod exec nginx nginx -s reload
```

---

## Useful Commands

```bash
# Check all containers
sudo docker compose -f docker-compose.prod.yml ps

# View logs
sudo docker compose -f docker-compose.prod.yml logs -f api
sudo docker compose -f docker-compose.prod.yml logs -f admin-web
sudo docker compose -f docker-compose.prod.yml logs --tail=50 nginx

# Restart a single service
sudo docker compose -f docker-compose.prod.yml --env-file .env.prod up -d api

# Check memory usage
free -h
sudo docker stats --no-stream

# Test endpoints
curl https://api.nexchool.in/api/health
curl -I https://app.nexchool.in
curl -I https://panel.nexchool.in
```

---

## Upgrading EC2 Instance Type

1. Stop instance: **EC2 → Instance state → Stop**
2. Change type: **Actions → Instance settings → Change instance type**
3. Start instance: **Instance state → Start**
4. Elastic IP stays attached — no DNS changes needed
5. Update `docker-compose.prod.yml` resource limits to match new instance

---

## Cost Estimate (ap-south-1)

| Service | Spec | Monthly |
|---------|------|---------|
| EC2 t3.small | 2 vCPU, 2GB | ~$18 |
| RDS db.t3.micro | PostgreSQL 16, 20GB | ~$14 |
| ECR storage | 3 repos ~3GB | ~$0.90 |
| Elastic IP | attached to running instance | free |
| Data transfer | ~10GB out | ~$1 |
| **Total** | | **~$34/month** |
