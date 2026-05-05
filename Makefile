.PHONY: dev clean seed-permissions

dev:
	./scripts/dev.sh

# Seed global RBAC permissions and default roles (runs server/scripts/seed_rbac.py in the api container).
seed-permissions:
	docker compose -f docker-compose.local.yml --env-file env/.env.local run --rm api python -m scripts.seed_rbac

clean:
	docker compose -f docker-compose.local.yml down --remove-orphans
	docker volume rm school-erp-local_admin_web_node_modules school-erp-local_panel_node_modules 2>/dev/null || true
