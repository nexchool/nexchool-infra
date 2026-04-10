.PHONY: dev prod deploy-prod clean clean-dev

dev:
	./scripts/dev.sh

prod:
	./scripts/prod.sh

deploy-prod:
	./scripts/deploy.sh prod

# Remove node_modules volumes so the next `make dev` reinstalls inside the container.
# Postgres data is preserved. Use `make clean` when you see native binary errors
# (lightningcss, etc.) or after adding new npm dependencies that weren't picked up.
clean:
	docker compose -f docker/docker-compose.local.yml down --remove-orphans
	docker volume rm school-erp-local_admin_web_node_modules school-erp-local_panel_node_modules || true

# Full clean + restart in one shot.
clean-dev: clean dev
