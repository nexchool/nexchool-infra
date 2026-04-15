#!/usr/bin/env sh
set -eu
# ECR / EC2 stack (pull images — no local build)
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
exec docker compose -f docker/docker-compose.ecr.yml --env-file env/.env.prod up -d "$@"
