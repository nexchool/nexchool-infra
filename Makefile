.PHONY: dev staging prod deploy-staging deploy-prod

dev:
	./scripts/dev.sh

staging:
	./scripts/staging.sh

prod:
	./scripts/prod.sh

deploy-staging:
	./scripts/deploy.sh staging

deploy-prod:
	./scripts/deploy.sh prod
