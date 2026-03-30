# 🚀 School ERP – Production Deployment Cheat Sheet

## 🧱 Infra Overview

* **Region:** ap-south-1 (Mumbai)
* **Infra Tool:** Terraform
* **EC2:** t4g.micro (⚠️ ARM64)
* **Services:**

  * API (Flask)
  * Admin Web (Next.js)
  * Panel (Next.js)
  * Redis
  * Nginx (reverse proxy)
* **Database:** RDS PostgreSQL
* **Registry:** AWS ECR
* **Storage:** S3

---

## 🔁 Deployment Flow

```text
git push → GitHub Actions → build (multi-arch) → push to ECR
→ SSH EC2 → docker compose pull → docker compose up -d
```

---

## ⚠️ Critical Rules

### 1. ARM Instance (IMPORTANT)

EC2 is ARM → ALWAYS build multi-arch images:

```yaml
docker buildx build \
  --platform linux/amd64,linux/arm64 \
  --push ...
```

---

### 2. ENV Handling

* Source of truth: **Terraform (`prod.tfvars`)**
* Generated at:

```bash
/home/ec2-user/app/.env
```

---

### 3. Nginx Routing

| Route / host | Service   |
| ------------ | --------- |
| `/` (default `server_name`) | admin-web |
| Dedicated Host for panel (e.g. `panel.example.com` from Terraform `panel_server_name`) | panel |
| `/api` | backend   |

The panel app uses **root paths** (`/login`, `/dashboard`). Route it with a **separate `server_name`** (subdomain), not a `/panel` URL prefix.

---

### 4. Panel build (Next.js)

`NEXT_PUBLIC_API_URL` (and related `NEXT_PUBLIC_*` vars) must be set at **Docker build** time for the panel image.

---

## 🛠️ Common Commands (EC2)

### SSH

```bash
ssh -i ~/.ssh/school-erp-prod.pem ec2-user@<EIP>
```

---

### Check containers

```bash
sudo docker compose ps
```

---

### Logs

```bash
sudo docker compose logs -f
sudo docker compose logs -f api
sudo docker compose logs -f nginx
```

---

### Restart services

```bash
sudo docker compose down
sudo docker compose up -d
```

---

### Pull latest images

```bash
sudo docker compose pull
sudo docker compose up -d
```

---

## 🔍 Debug Checklist

### ❌ Site not loading

* Check SG → port 80 open
* Check nginx logs

---

### ❌ API down

```bash
docker compose logs api
```

---

### ❌ Frontend not loading

* Check:

```bash
docker compose logs admin-web
docker compose logs panel
```

---

### ❌ `exec format error`

👉 Image built for wrong arch
✔ Fix: multi-arch build

---

### ❌ 502 Bad Gateway

👉 Upstream container not reachable
✔ Check container status

---

### ❌ Panel redirect loop

👉 Auth cookie / middleware / wrong Host (panel must hit the panel container, not admin-web)
✔ Check `panel_server_name` in Terraform + DNS; verify `NEXT_PUBLIC_API_URL` at image build time

---

### ❌ Panel assets 404

👉 Old build cache
✔ Force rebuild (`--no-cache`)

---

## 🔐 GitHub Actions Setup

### Required Secrets (per repo)

```
AWS_ROLE_TO_ASSUME_PROD
ECR_REPO_*
EC2_HOST_PROD
EC2_SSH_PRIVATE_KEY
NEXT_PUBLIC_API_URL_PROD
```

---

### OIDC Trust Policy

* Must match:

```
repo:nexchool/<repo>:ref:refs/heads/main
```

---

## 🔁 When You Change Something

### Code change

```bash
git push origin main
```

---

### ENV change

```bash
terraform apply -var-file=prod.tfvars
terraform taint aws_instance.ec2
terraform apply -var-file=prod.tfvars
```

---

### Infra change

```bash
terraform apply
```

---

## 🌐 URLs

```
http://<EIP>/          → Admin Web
http://<panel-host>/   → Panel (same EIP, different Host — set `panel_server_name` in Terraform)
http://<EIP>/api/health → API
```

---

## 🧠 Golden Rules

* Infra → Terraform
* Runtime → Docker
* Deploy → GitHub Actions
* Never commit secrets
* Always use multi-arch builds

---

## ✅ Final State Checklist

* [ ] All containers `Up (healthy)`
* [ ] API `/api/health` works
* [ ] Admin loads
* [ ] Panel loads
* [ ] No nginx errors

---

🔥 If everything above is true → **PRODUCTION IS LIVE**
