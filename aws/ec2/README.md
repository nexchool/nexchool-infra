# EC2 runtime layout

On the instance, Terraform creates:

```text
/home/ec2-user/app/
  docker-compose.yml   # rendered from ../terraform/templates/docker-compose.yml.tpl
  nginx.conf           # rendered from ../terraform/templates/nginx.conf.tpl
  .env                 # rendered from ../terraform/templates/env.tpl
```

**Source of truth:** Terraform templates under `aws/terraform/templates/`. Files in `aws/ec2/` are reference copies (ECR placeholders / HTTP nginx baseline).

To change routing, env, or ports, update templates and `prod.tfvars`, then replace the EC2 instance so `user_data` rewrites these files (avoid ad-hoc edits on the server for production).

## HTTPS (Certbot) — manual follow-up

1. Point your domain A record to the Elastic IP (`terraform output ec2_elastic_ip`).
2. SSH to the instance, install Certbot for nginx, obtain certificates.
3. Add a `server { listen 443 ssl; ... }` block in `nginx.conf` (or an included snippet) and reload nginx.

The HTTP `server` block in `nginx.conf` is ready for you to extend.

## Basic Server Monitoring (EC2)

After SSH to the instance:

| Command | What it shows |
|--------|----------------|
| `htop` | CPU and process usage (`sudo dnf install -y htop` on Amazon Linux if not installed) |
| `free -h` | Memory and swap |
| `docker stats` | Per-container CPU/memory |
| `df -h` | Disk usage |
