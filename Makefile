.PHONY: dev prod deploy-prod

dev:
	./scripts/dev.sh

prod:
	./scripts/prod.sh

deploy-prod:
	./scripts/deploy.sh prod
