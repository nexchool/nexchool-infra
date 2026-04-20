.PHONY: dev clean

dev:
	./scripts/dev.sh

clean:
	docker compose -f docker-compose.local.yml down --remove-orphans
	docker volume rm school-erp-local_admin_web_node_modules school-erp-local_panel_node_modules 2>/dev/null || true
