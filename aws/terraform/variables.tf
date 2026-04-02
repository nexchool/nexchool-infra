variable "project_name" {
  description = "Project slug."
  type        = string
  default     = "school-erp"
}

variable "environment" {
  description = "Environment name (staging or prod)."
  type        = string
}

variable "aws_region" {
  description = "AWS region."
  type        = string
  default     = "ap-south-1"
}

variable "vpc_cidr" {
  description = "VPC CIDR."
  type        = string
}

variable "public_subnet_cidrs" {
  description = "Two public subnet CIDRs (multi-AZ RDS)."
  type        = list(string)
}

variable "ec2_instance_type" {
  description = "EC2 size — t4g.micro (ARM) or t3.micro (x86) for lowest cost."
  type        = string
  default     = "t4g.micro"
}

variable "ec2_key_name" {
  description = "Existing EC2 Key Pair name for SSH."
  type        = string
}

variable "ssh_cidr" {
  description = "CIDR allowed for SSH (e.g. your public IP /32)."
  type        = string
}

variable "ec2_root_volume_gb" {
  description = "Root disk size for Docker images."
  type        = number
  default     = 30
}

variable "db_instance_class" {
  description = "RDS instance class."
  type        = string
  default     = "db.t4g.micro"
}

variable "db_name" {
  description = "Database name."
  type        = string
}

variable "db_username" {
  description = "Database username."
  type        = string
}

variable "db_password" {
  description = "RDS master password (8–128 chars; no / @ \" or space — AWS rule)."
  type        = string
  sensitive   = true

  validation {
    condition = (
      length(var.db_password) >= 8 &&
      length(var.db_password) <= 128 &&
      length(regexall("[/@\" ]", var.db_password)) == 0
    )
    error_message = "db_password must be 8-128 characters and cannot contain /, @, double-quote (\"), or space (AWS RDS requirement)."
  }
}

variable "secret_key" {
  description = "Flask SECRET_KEY."
  type        = string
  sensitive   = true
}

variable "jwt_secret_key" {
  description = "Flask JWT_SECRET_KEY."
  type        = string
  sensitive   = true
}

variable "cors_origins" {
  description = "CORS_ORIGINS value (comma-separated)."
  type        = string
}

# --- Public URLs (single .env on EC2 for api + Next apps) ---
variable "app_public_base_url" {
  description = "Public base URL for BACKEND_URL and browser API calls when NEXT_PUBLIC_API_URL is unset (e.g. https://erp.example.com). Empty = http://<Elastic IP> at apply time."
  type        = string
  default     = ""
}

variable "next_public_api_url" {
  description = "Override NEXT_PUBLIC_API_URL for admin-web/panel only. Empty = same as app_public_base_url (or EIP URL)."
  type        = string
  default     = ""
}

variable "panel_server_name" {
  description = "If set, nginx adds a server block for this Host routing / to the panel container (super admin). Use your panel subdomain, e.g. panel.example.com. Empty = no panel vhost (use direct container port or a manual nginx snippet)."
  type        = string
  default     = ""
}

variable "frontend_url" {
  description = "FRONTEND_URL (e.g. mobile deep link base)."
  type        = string
  default     = "schoolerp://"
}

variable "default_tenant_subdomain" {
  type    = string
  default = "default"
}

variable "default_user_role" {
  description = "DEFAULT_USER_ROLE for auth registration defaults (e.g. Student)."
  type        = string
  default     = "Student"
}

# --- Flask ---
variable "flask_app" {
  description = "FLASK_APP WSGI entry."
  type        = string
  default     = "backend.app:create_app"
}

variable "flask_debug" {
  description = "FLASK_DEBUG (False for production)."
  type        = string
  default     = "False"
}

variable "session_cookie_secure" {
  type    = string
  default = "true"
}

variable "session_cookie_samesite" {
  type    = string
  default = "Lax"
}

variable "jwt_access_token_expires_minutes" {
  type    = number
  default = 15
}

variable "jwt_refresh_token_expires_days" {
  type    = number
  default = 7
}

variable "reset_token_exp_minutes" {
  type    = number
  default = 30
}

# --- Mail (optional) ---
variable "smtp_server" {
  type    = string
  default = ""
}

variable "smtp_port" {
  type    = number
  default = 587
}

variable "email_address" {
  type    = string
  default = ""
}

variable "email_password" {
  type      = string
  default   = ""
  sensitive = true
}

variable "default_sender_name" {
  type    = string
  default = ""
}

variable "mail_use_tls" {
  description = "MAIL_USE_TLS for Flask-Mail."
  type        = string
  default     = "true"
}

variable "mail_use_ssl" {
  description = "MAIL_USE_SSL for Flask-Mail."
  type        = string
  default     = "false"
}

# --- Redis (Compose service names) ---
variable "redis_url" {
  type    = string
  default = "redis://redis:6379/0"
}

variable "celery_broker_url" {
  type    = string
  default = "redis://redis:6379/0"
}

variable "celery_result_backend" {
  type    = string
  default = "redis://redis:6379/0"
}

# --- API port / Gunicorn (non-secret tuning) ---
variable "api_port" {
  type    = number
  default = 5001
}

variable "web_concurrency" {
  type    = number
  default = 1
}

variable "gunicorn_workers" {
  type    = number
  default = 1
}

variable "gunicorn_threads" {
  type    = number
  default = 2
}

variable "gunicorn_timeout" {
  type    = number
  default = 60
}

# --- Next.js (admin-web + panel; shared .env) ---
variable "node_env" {
  type    = string
  default = "production"
}

variable "next_telemetry_disabled" {
  type    = string
  default = "1"
}

variable "node_options" {
  type    = string
  default = "--max-old-space-size=128"
}

variable "next_public_gateway_origin" {
  description = "Optional NEXT_PUBLIC_GATEWAY_ORIGIN for admin-web/panel when opened on :3000 (empty = client falls back to hostname:80)."
  type        = string
  default     = ""
}

# --- S3 (single shared bucket; app uses S3_ENV_PREFIX for local/prod keys) ---
variable "app_storage_bucket_name" {
  description = "Override S3 bucket name for app files. Empty = {project}-{environment}-documents-{account_id}."
  type        = string
  default     = ""
}

variable "s3_env_prefix" {
  description = "Object key prefix written to AWS_S3_BUCKET_NAME / S3_BUCKET_NAME (e.g. prod). Empty = same as environment variable."
  type        = string
  default     = ""
}
