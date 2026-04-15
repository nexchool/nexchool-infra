.PHONY: dev prod deploy-prod deploy-ecr clean clean-dev

dev:
	./scripts/dev.sh

# Build images from source + Postgres (production-like on your machine / VM)
prod:
	./scripts/prod.sh

# Same as prod but runs git pull on server/admin/panel repos first (see scripts/deploy.sh)
deploy-prod:
	./scripts/deploy.sh prod

# Pull ECR images + up (AWS / pre-built images — no git pull of app repos)
deploy-ecr:
	./scripts/deploy.sh ecr

# Remove node_modules volumes so the next `make dev` reinstalls inside the container.
clean:
	docker compose -f docker/docker-compose.local.yml down --remove-orphans
	docker volume rm school-erp-local_admin_web_node_modules school-erp-local_panel_node_modules 2>/dev/null || true

clean-dev: clean dev
