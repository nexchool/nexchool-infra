# Generated on first boot — ECR images + nginx + Redis (API/Celery)
# Resource limits: require Docker Compose v2.20+ (deploy.resources applied on `compose up`)
#
# Do NOT set platform: linux/amd64 on API/Celery when EC2 is ARM (e.g. t4g): the image is
# multi-arch (CI builds amd64+arm64); pinning amd64 on an aarch64 host causes exec format error
# unless QEMU binfmt is installed. Omit platform so Docker pulls the native variant.
x-logging: &json-logging
  driver: json-file
  options:
    max-size: "10m"
    max-file: "3"

services:
  redis:
    image: redis:7-alpine
    command: redis-server --maxmemory 64mb --maxmemory-policy allkeys-lru
    restart: unless-stopped
    stop_grace_period: 30s
    logging: *json-logging
    deploy:
      resources:
        limits:
          cpus: "0.10"
          memory: 100M
    healthcheck:
      test: ["CMD", "redis-cli", "ping"]
      interval: 5s
      timeout: 3s
      retries: 5

  api:
    image: ${ecr_api_url}:latest
    restart: unless-stopped
    stop_grace_period: 30s
    logging: *json-logging
    deploy:
      resources:
        limits:
          cpus: "0.50"
          memory: 300M
    ulimits:
      nofile:
        soft: 65536
        hard: 65536
    env_file:
      - .env
    expose:
      - "${api_port}"
    healthcheck:
      test: ["CMD", "curl", "-fsS", "http://127.0.0.1:${api_port}/api/health"]
      interval: 30s
      timeout: 5s
      retries: 3
      start_period: 90s
    depends_on:
      redis:
        condition: service_healthy

  # Same API image; overrides entrypoint to run Celery worker (send_email_task, etc.).
  # Without this service, tasks are queued to Redis but never consumed.
  celery-worker:
    image: ${ecr_api_url}:latest
    restart: unless-stopped
    stop_grace_period: 30s
    logging: *json-logging
    deploy:
      resources:
        limits:
          cpus: "0.25"
          memory: 200M
    env_file:
      - .env
    entrypoint: ["celery", "-A", "backend.celery_worker:celery", "worker", "-l", "info"]
    depends_on:
      redis:
        condition: service_healthy
      api:
        condition: service_healthy

  # Scheduled tasks (e.g. finance beat schedule in celery_app).
  celery-beat:
    image: ${ecr_api_url}:latest
    restart: unless-stopped
    stop_grace_period: 30s
    logging: *json-logging
    deploy:
      resources:
        limits:
          cpus: "0.10"
          memory: 100M
    env_file:
      - .env
    entrypoint: ["celery", "-A", "backend.celery_worker:celery", "beat", "-l", "info"]
    depends_on:
      redis:
        condition: service_healthy
      api:
        condition: service_healthy

  admin-web:
    image: ${ecr_admin_web_url}:latest
    restart: unless-stopped
    stop_grace_period: 30s
    logging: *json-logging
    deploy:
      resources:
        limits:
          cpus: "0.25"
          memory: 200M
    env_file:
      - .env
    expose:
      - "3000"
    depends_on:
      api:
        condition: service_healthy

  panel:
    image: ${ecr_panel_url}:latest
    restart: unless-stopped
    stop_grace_period: 30s
    logging: *json-logging
    deploy:
      resources:
        limits:
          cpus: "0.25"
          memory: 200M
    env_file:
      - .env
    expose:
      - "3000"
    depends_on:
      api:
        condition: service_healthy

  nginx:
    image: nginx:1.27-alpine
    restart: unless-stopped
    stop_grace_period: 30s
    logging: *json-logging
    deploy:
      resources:
        limits:
          cpus: "0.10"
          memory: 50M
    ulimits:
      nofile:
        soft: 65536
        hard: 65536
    extra_hosts:
      - "host.docker.internal:host-gateway"
    ports:
      - "80:80"
    volumes:
      - ./nginx.conf:/etc/nginx/nginx.conf:ro
    depends_on:
      api:
        condition: service_healthy
      admin-web:
        condition: service_started
      panel:
        condition: service_started
