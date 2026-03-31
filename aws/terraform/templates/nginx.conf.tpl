user  nginx;
worker_processes  auto;

error_log  /dev/stderr warn;
pid        /var/run/nginx.pid;

events {
  worker_connections 1024;
}

http {
  include       /etc/nginx/mime.types;
  default_type  application/octet-stream;

  proxy_set_header Host              $host;
  proxy_set_header X-Real-IP         $remote_addr;
  proxy_set_header X-Forwarded-For   $proxy_add_x_forwarded_for;
  proxy_set_header X-Forwarded-Proto $scheme;
  proxy_http_version 1.1;
  proxy_set_header Upgrade $http_upgrade;
  proxy_set_header Connection "upgrade";
  proxy_read_timeout 60s;

  access_log /dev/stdout;

  upstream api_upstream {
    server api:${api_port};
  }

  upstream admin_web {
    server admin-web:3000;
  }

  upstream panel_upstream {
    server panel:3000;
  }

  # Marketing site — Next.js on EC2 host (PM2), not in Docker (see docker-compose nginx extra_hosts).
  upstream landing_upstream {
    server host.docker.internal:7000;
  }

  server {
    listen 80;
    server_name nexchool.in www.nexchool.in;

    location / {
      proxy_pass http://landing_upstream;
    }
  }

%{ if trimspace(panel_server_name) != "" ~}
  # Super admin panel (dedicated Host — no /panel path prefix in the app)
  server {
    listen 80;
    server_name ${panel_server_name};

    location / {
      proxy_pass http://panel_upstream;
    }
  }

%{ endif ~}
  # Default: school admin + API paths (same Docker network)
  server {
    listen 80;
    server_name _;

    location ^~ /api/ {
      proxy_pass http://api_upstream;
    }
    location = /api {
      proxy_pass http://api_upstream;
    }

    location = /health {
      proxy_pass http://api_upstream;
    }

    location / {
      proxy_pass http://admin_web;
    }
  }

  # Future HTTPS (Certbot): add a second server { listen 443 ssl; ... }
  # and certificates under /etc/letsencrypt/ — see AWS_DEPLOYMENT_GUIDE.md
}
