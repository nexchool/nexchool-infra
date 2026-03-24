#!/bin/bash
# Amazon Linux 2023 — swap, Docker + Compose + app stack
set -euxo pipefail

dnf update -y
dnf install -y docker aws-cli
systemctl enable --now docker

# --- Swap (before containers start; reduces OOM on 1GB instances) ---
if ! swapon --show | grep -q swapfile; then
  fallocate -l 1G /swapfile 2>/dev/null || dd if=/dev/zero of=/swapfile bs=1M count=1024
  chmod 600 /swapfile
  mkswap /swapfile
  swapon /swapfile
  grep -q '/swapfile' /etc/fstab || echo '/swapfile none swap sw 0 0' >> /etc/fstab
fi

# Docker Compose v2 (plugin)
if ! dnf install -y docker-compose-plugin 2>/dev/null; then
  mkdir -p /usr/local/lib/docker/cli-plugins /usr/libexec/docker/cli-plugins
  ARCH="$(uname -m)"
  case "$ARCH" in
    aarch64) DC_ARCH="aarch64" ;;
    x86_64)  DC_ARCH="x86_64" ;;
    *) DC_ARCH="x86_64" ;;
  esac
  curl -fsSL "https://github.com/docker/compose/releases/download/v2.29.7/docker-compose-linux-$${DC_ARCH}" \
    -o /usr/local/lib/docker/cli-plugins/docker-compose
  chmod +x /usr/local/lib/docker/cli-plugins/docker-compose
  ln -sf /usr/local/lib/docker/cli-plugins/docker-compose /usr/libexec/docker/cli-plugins/docker-compose
fi

usermod -aG docker ec2-user

mkdir -p /home/ec2-user/app
echo "${docker_compose_b64}" | base64 -d > /home/ec2-user/app/docker-compose.yml
echo "${env_b64}" | base64 -d > /home/ec2-user/app/.env
echo "${nginx_b64}" | base64 -d > /home/ec2-user/app/nginx.conf
chown -R ec2-user:ec2-user /home/ec2-user/app
chmod 600 /home/ec2-user/app/.env

# ECR login (instance role) and start stack
cd /home/ec2-user/app
aws ecr get-login-password --region ${aws_region} | docker login --username AWS --password-stdin ${ecr_registry}
docker compose pull
docker compose up -d
