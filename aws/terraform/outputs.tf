output "ec2_elastic_ip" {
  description = "Stable public IP — use for DNS A record and BACKEND_URL updates."
  value       = aws_eip.app.public_ip
}

output "ec2_instance_id" {
  value = aws_instance.app.id
}

output "api_ecr_repository_url" {
  value = aws_ecr_repository.api.repository_url
}

output "admin_web_ecr_repository_url" {
  value = aws_ecr_repository.admin_web.repository_url
}

output "panel_ecr_repository_url" {
  value = aws_ecr_repository.panel.repository_url
}

output "ecr_registry_url" {
  description = "Registry host for docker login (same for all repos in this account/region)."
  value       = "${data.aws_caller_identity.current.account_id}.dkr.ecr.${var.aws_region}.amazonaws.com"
}

output "s3_bucket_name" {
  description = "App storage bucket (single bucket; keys use S3_ENV_PREFIX in the app)."
  value       = aws_s3_bucket.documents.bucket
}

output "s3_bucket_arn" {
  description = "ARN of the app storage bucket."
  value       = aws_s3_bucket.documents.arn
}

output "rds_endpoint" {
  value = aws_db_instance.postgres.address
}

output "app_http_url" {
  description = "Effective public app URL (app_public_base_url or http://EIP). Matches BACKEND_URL / NEXT_PUBLIC_API_URL in .env unless overridden."
  value       = local.effective_public_base_url
}
