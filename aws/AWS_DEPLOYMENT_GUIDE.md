# AWS deployment (EC2 + ECR + RDS)

Terraform is **not** used in this repo. Application deployment is driven entirely by **`school-erp-infra/`**.

## What to use

- **Compose file:** `docker/docker-compose.ecr.yml` (pulls ECR images).
- **Env:** `env/.env.prod` (copy from `env/.env.prod.example`).
- **Nginx:** `nginx/nginx.prod.conf`.
- **Operations:** see **`../README.md`** in `school-erp-infra` (EC2 copy layout, `docker compose … up -d`, pull + redeploy).

On the EC2 host, either clone the monorepo and `cd school-erp-infra`, or rsync the `school-erp-infra/` directory to `/home/ec2-user/app` and run Compose from there with paths as documented in the main README.
