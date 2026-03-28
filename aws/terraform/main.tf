terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.90"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

data "aws_availability_zones" "available" {
  state = "available"
}

data "aws_caller_identity" "current" {}

locals {
  name_prefix = "${var.project_name}-${var.environment}"
  azs         = slice(data.aws_availability_zones.available.names, 0, 2)
  is_arm      = startswith(var.ec2_instance_type, "t4g") || startswith(var.ec2_instance_type, "m7g") || startswith(var.ec2_instance_type, "c7g")
}

# Amazon Linux 2023 — match instance architecture (ARM for t4g.*, x86 for t3.*)
data "aws_ami" "al2023" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = [local.is_arm ? "al2023-ami-*-arm64" : "al2023-ami-*-x86_64"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  filter {
    name   = "state"
    values = ["available"]
  }
}

resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "${local.name_prefix}-vpc"
  }
}

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id
  tags = {
    Name = "${local.name_prefix}-igw"
  }
}

resource "aws_subnet" "public" {
  count                   = 2
  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.public_subnet_cidrs[count.index]
  availability_zone       = local.azs[count.index]
  map_public_ip_on_launch = true

  tags = {
    Name = "${local.name_prefix}-public-${count.index + 1}"
  }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = {
    Name = "${local.name_prefix}-public-rt"
  }
}

resource "aws_route_table_association" "public_assoc" {
  count          = 2
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

# --- EC2 security group (HTTP/HTTPS + SSH) ---
resource "aws_security_group" "ec2" {
  name        = "${local.name_prefix}-ec2-sg"
  description = "Web + SSH for app host"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTPS (future Certbot)"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "SSH (restricted)"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.ssh_cidr]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${local.name_prefix}-ec2-sg"
  }
}

# --- RDS: Postgres only from EC2 ---
resource "aws_security_group" "rds" {
  name        = "${local.name_prefix}-rds-sg"
  description = "Postgres from EC2 only"
  vpc_id      = aws_vpc.main.id

  ingress {
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.ec2.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${local.name_prefix}-rds-sg"
  }
}

resource "aws_ecr_repository" "api" {
  name                 = "${local.name_prefix}-api"
  image_tag_mutability = "MUTABLE"
}

resource "aws_ecr_repository" "admin_web" {
  name                 = "${local.name_prefix}-admin-web"
  image_tag_mutability = "MUTABLE"
}

resource "aws_ecr_repository" "panel" {
  name                 = "${local.name_prefix}-panel"
  image_tag_mutability = "MUTABLE"
}

resource "aws_s3_bucket" "documents" {
  bucket = "${local.name_prefix}-documents-${data.aws_caller_identity.current.account_id}"
}

resource "aws_s3_bucket_public_access_block" "documents" {
  bucket                  = aws_s3_bucket.documents.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_versioning" "documents" {
  bucket = aws_s3_bucket.documents.id
  versioning_configuration {
    status = "Enabled"
  }
}

# RDS in public subnets (no NAT); not publicly accessible — private IP only
resource "aws_db_subnet_group" "main" {
  name       = "${local.name_prefix}-db-subnets"
  subnet_ids = aws_subnet.public[*].id
}

resource "aws_db_instance" "postgres" {
  identifier = "${local.name_prefix}-postgres"
  engine     = "postgres"
  # Omit engine_version: ap-south-1 (and other regions) may not offer every minor (e.g. 16.3).
  # RDS picks the current default PostgreSQL major; use auto_minor_version_upgrade for patches.
  instance_class         = var.db_instance_class
  allocated_storage      = 20
  max_allocated_storage  = 100
  db_name                = var.db_name
  username               = var.db_username
  password               = var.db_password
  publicly_accessible    = false
  db_subnet_group_name   = aws_db_subnet_group.main.name
  vpc_security_group_ids = [aws_security_group.rds.id]
  multi_az               = false
  skip_final_snapshot    = true
  deletion_protection    = false
}

# --- IAM role for EC2: ECR pull + S3 + optional CloudWatch Logs ---
resource "aws_iam_role" "ec2" {
  name = "${local.name_prefix}-ec2-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "ec2.amazonaws.com"
      }
    }]
  })
}

resource "aws_iam_role_policy" "ec2_ecr" {
  name = "${local.name_prefix}-ecr-pull"
  role = aws_iam_role.ec2.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ecr:GetAuthorizationToken"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "ecr:BatchGetImage",
          "ecr:GetDownloadUrlForLayer"
        ]
        Resource = [
          aws_ecr_repository.api.arn,
          aws_ecr_repository.admin_web.arn,
          aws_ecr_repository.panel.arn
        ]
      }
    ]
  })
}

resource "aws_iam_role_policy" "ec2_s3" {
  name = "${local.name_prefix}-s3-documents"
  role = aws_iam_role.ec2.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:PutObject",
          "s3:GetObject",
          "s3:DeleteObject"
        ]
        Resource = "${aws_s3_bucket.documents.arn}/*"
      },
      {
        Effect   = "Allow"
        Action   = ["s3:ListBucket"]
        Resource = aws_s3_bucket.documents.arn
      }
    ]
  })
}

resource "aws_iam_role_policy" "ec2_logs_optional" {
  name = "${local.name_prefix}-cw-logs"
  role = aws_iam_role.ec2.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
          "logs:DescribeLogStreams"
        ]
        Resource = "arn:aws:logs:${var.aws_region}:${data.aws_caller_identity.current.account_id}:log-group:/ec2/${local.name_prefix}/*"
      }
    ]
  })
}

resource "aws_iam_instance_profile" "ec2" {
  name = "${local.name_prefix}-ec2-profile"
  role = aws_iam_role.ec2.name
}

locals {
  database_url = "postgresql://${var.db_username}:${var.db_password}@${aws_db_instance.postgres.address}:5432/${var.db_name}"
  # Public URL for Flask BACKEND_URL, CORS, and Next.js NEXT_PUBLIC_API_URL (unless overridden).
  effective_public_base_url = trimspace(var.app_public_base_url) != "" ? var.app_public_base_url : "http://${aws_eip.app.public_ip}"
  next_public_api_url       = trimspace(var.next_public_api_url) != "" ? var.next_public_api_url : local.effective_public_base_url
}

resource "aws_eip" "app" {
  domain = "vpc"
  tags = {
    Name = "${local.name_prefix}-app-eip"
  }
}

resource "aws_instance" "app" {
  ami                    = data.aws_ami.al2023.id
  instance_type          = var.ec2_instance_type
  subnet_id              = aws_subnet.public[0].id
  vpc_security_group_ids = [aws_security_group.ec2.id]
  key_name               = var.ec2_key_name
  iam_instance_profile   = aws_iam_instance_profile.ec2.name

  user_data = base64encode(templatefile("${path.module}/templates/user_data.sh.tpl", {
    docker_compose_b64 = base64encode(templatefile("${path.module}/templates/docker-compose.yml.tpl", {
      ecr_api_url       = aws_ecr_repository.api.repository_url
      ecr_admin_web_url = aws_ecr_repository.admin_web.repository_url
      ecr_panel_url     = aws_ecr_repository.panel.repository_url
      api_port          = var.api_port
    }))
    env_b64 = base64encode(templatefile("${path.module}/templates/env.tpl", {
      database_url                     = local.database_url
      redis_url                        = var.redis_url
      celery_broker_url                = var.celery_broker_url
      celery_result_backend            = var.celery_result_backend
      flask_app                        = var.flask_app
      flask_env                        = var.environment == "prod" ? "production" : "staging"
      flask_debug                      = var.flask_debug
      secret_key                       = var.secret_key
      jwt_secret_key                   = var.jwt_secret_key
      jwt_access_token_expires_minutes = var.jwt_access_token_expires_minutes
      jwt_refresh_token_expires_days   = var.jwt_refresh_token_expires_days
      reset_token_exp_minutes          = var.reset_token_exp_minutes
      default_tenant_subdomain         = var.default_tenant_subdomain
      default_user_role                = var.default_user_role
      backend_url                      = local.effective_public_base_url
      frontend_url                     = var.frontend_url
      cors_origins                     = var.cors_origins
      session_cookie_secure            = var.session_cookie_secure
      session_cookie_samesite          = var.session_cookie_samesite
      smtp_server                      = var.smtp_server
      smtp_port                        = var.smtp_port
      email_address                    = var.email_address
      email_password                   = var.email_password
      default_sender_name              = var.default_sender_name
      mail_use_tls                     = var.mail_use_tls
      mail_use_ssl                     = var.mail_use_ssl
      aws_region                       = var.aws_region
      s3_bucket_name                   = aws_s3_bucket.documents.bucket
      port                             = var.api_port
      gunicorn_bind                    = "0.0.0.0:${var.api_port}"
      web_concurrency                  = var.web_concurrency
      gunicorn_workers                 = var.gunicorn_workers
      gunicorn_threads                 = var.gunicorn_threads
      gunicorn_timeout                 = var.gunicorn_timeout
      node_env                         = var.node_env
      next_telemetry_disabled          = var.next_telemetry_disabled
      node_options                     = var.node_options
      next_public_api_url              = local.next_public_api_url
      next_public_gateway_origin       = var.next_public_gateway_origin
    }))
    nginx_b64 = base64encode(templatefile("${path.module}/templates/nginx.conf.tpl", {
      api_port = var.api_port
    }))
    aws_region   = var.aws_region
    ecr_registry = "${data.aws_caller_identity.current.account_id}.dkr.ecr.${var.aws_region}.amazonaws.com"
  }))

  root_block_device {
    volume_size = var.ec2_root_volume_gb
    volume_type = "gp3"
  }

  depends_on = [aws_db_instance.postgres, aws_eip.app]

  tags = {
    Name = "${local.name_prefix}-app"
  }
}

resource "aws_eip_association" "app" {
  instance_id   = aws_instance.app.id
  allocation_id = aws_eip.app.id
}
