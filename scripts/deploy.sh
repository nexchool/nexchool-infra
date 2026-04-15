#!/usr/bin/env sh
set -eu

# Usage: ./scripts/deploy.sh [prod]
# Pulls app repos (paths from the matching env file), then rebuilds that stack.
# SERVER_CONTEXT / *_CONTEXT values are relative to school-erp-infra/docker/
# (same as Docker Compose), e.g. ../../server when infra is school-ERP/school-erp-infra/.

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
COMPOSE_DIR="$ROOT/docker"

TARGET="${1:-prod}"
case "$TARGET" in
  prod)
    ENV_FILE="$ROOT/env/.env.prod"
    COMPOSE_FILE="docker/docker-compose.prod.yml"
    ;;
  ecr)
    cd "$ROOT"
    docker compose -f docker/docker-compose.ecr.yml --env-file env/.env.prod pull
    docker compose -f docker/docker-compose.ecr.yml --env-file env/.env.prod up -d
    echo ">>> Deploy (ecr) done."
    exit 0
    ;;
  *)
    echo "Usage: $0 [prod|ecr]" >&2
    exit 1
    ;;
esac

read_env_var() {
  key="$1"
  default="$2"
  line="$(grep -E "^${key}=" "$ENV_FILE" 2>/dev/null | head -1 || true)"
  val="${line#*=}"
  if [ -n "$val" ]; then
    printf '%s' "$val"
  else
    printf '%s' "$default"
  fi
}

# Defaults match nested layout: monorepo/school-erp-infra → ../../app
SERVER_DIR="$(read_env_var SERVER_CONTEXT ../../server)"
ADMIN_DIR="$(read_env_var SCHOOL_ADMIN_CONTEXT ../../admin-web)"
PANEL_DIR="$(read_env_var SUPER_ADMIN_CONTEXT ../../panel)"

resolve_context_path() {
  rel="$1"
  case "$rel" in
    /*) printf '%s\n' "$rel" ;;
    *) (cd "$COMPOSE_DIR" && cd "$rel" && pwd -P) ;;
  esac
}

pull_if_git() {
  dir="$1"
  if [ -d "$dir/.git" ]; then
    echo ">>> git pull: $dir"
    git -C "$dir" pull --ff-only
  else
    echo ">>> skip (not a git repo): $dir"
  fi
}

pull_if_git "$(resolve_context_path "$SERVER_DIR")"
pull_if_git "$(resolve_context_path "$ADMIN_DIR")"
pull_if_git "$(resolve_context_path "$PANEL_DIR")"

cd "$ROOT"
docker compose -f "$COMPOSE_FILE" --env-file "$ENV_FILE" up -d --build

echo ">>> Deploy ($TARGET) done."
