.PHONY: dev seed seed-subjects seed-permissions migrate clean

# Bring up the full local stack. The api container's startup.sh already:
#   1. Waits for Postgres to be reachable.
#   2. Runs `flask db upgrade` (skipped if SKIP_DB_MIGRATE=1).
#   3. Runs the idempotent seed scripts (skipped if SKIP_DB_SEED=1).
#   4. Starts Gunicorn.
# So `make dev` covers migrations + seeds automatically; no manual step needed.
dev:
	./scripts/dev.sh

# Run the idempotent seed bundle against a running stack on demand.
# Mirrors the list inside server/startup.sh's run_seeds(); keep them in sync
# when adding new seeds.
seed:
	docker compose -f docker-compose.local.yml --env-file env/.env.local exec api python -m scripts.seed_rbac
	docker compose -f docker-compose.local.yml --env-file env/.env.local exec api python -m scripts.seed_holiday_permissions
	docker compose -f docker-compose.local.yml --env-file env/.env.local exec api python -m scripts.grant_hostel_permissions

# Run the subject-template seed manually. NOT idempotent — only invoke
# against a fresh DB or after a TRUNCATE; running twice errors on the
# UNIQUE constraint on template items.
seed-subjects:
	docker compose -f docker-compose.local.yml --env-file env/.env.local exec api python -m scripts.seed_subject_templates

# Legacy alias: seed RBAC permissions only.
seed-permissions:
	docker compose -f docker-compose.local.yml --env-file env/.env.local run --rm api python -m scripts.seed_rbac

# Apply outstanding migrations on demand (api container does this on startup
# anyway; this is for the case where you don't want to restart the stack).
migrate:
	docker compose -f docker-compose.local.yml --env-file env/.env.local exec api flask db upgrade

clean:
	docker compose -f docker-compose.local.yml down --remove-orphans
	docker volume rm school-erp-local_admin_web_node_modules school-erp-local_panel_node_modules 2>/dev/null || true
