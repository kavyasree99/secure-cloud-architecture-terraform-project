output "alb_dns_name" {
  description = "Public DNS name of the Application Load Balancer"
  value       = aws_lb.main.dns_name
}

output "ecr_api_repository_url" {
  description = "URL of the ECR repository to push API images to"
  value       = aws_ecr_repository.api.repository_url
}

output "ecr_worker_repository_url" {
  description = "URL of the ECR repository to push worker images to"
  value       = aws_ecr_repository.worker.repository_url
}

output "ecs_cluster_name" {
  description = "Name of the ECS cluster"
  value       = aws_ecs_cluster.main.name
}

output "ecs_api_service_name" {
  description = "Name of the public API ECS service"
  value       = aws_ecs_service.api.name
}

output "ecs_worker_service_name" {
  description = "Name of the private background worker ECS service"
  value       = aws_ecs_service.worker.name
}

output "rds_endpoint" {
  description = "Connection endpoint for the RDS instance"
  value       = aws_db_instance.main.address
  sensitive   = true
}

output "sqs_queue_url" {
  description = "URL of the application SQS queue"
  value       = aws_sqs_queue.app.url
}

output "s3_bucket_name" {
  description = "Name of the application S3 bucket"
  value       = aws_s3_bucket.app.bucket
}

output "db_credentials_secret_arn" {
  description = "ARN of the Secrets Manager secret holding DB credentials"
  value       = aws_secretsmanager_secret.db_credentials.arn
}

output "vpc_id" {
  description = "ID of the VPC"
  value       = aws_vpc.main.id
}
