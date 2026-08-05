variable "aws_region" {
  description = "AWS region to deploy into"
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Short name used to prefix/tag resources"
  type        = string
  default     = "devops-assignment"
}

variable "environment" {
  description = "Deployment environment name"
  type        = string
  default     = "dev"
}

# ---------------------------------------------------------------------------
# Networking
# ---------------------------------------------------------------------------

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "availability_zones" {
  description = "Availability zones to spread subnets across"
  type        = list(string)
  default     = ["us-east-1a", "us-east-1b"]
}

variable "public_subnet_cidrs" {
  description = "CIDR blocks for public subnets (one per AZ)"
  type        = list(string)
  default     = ["10.0.0.0/24", "10.0.1.0/24"]
}

variable "private_subnet_cidrs" {
  description = "CIDR blocks for private application subnets (one per AZ)"
  type        = list(string)
  default     = ["10.0.10.0/24", "10.0.11.0/24"]
}

variable "database_subnet_cidrs" {
  description = "CIDR blocks for private database subnets (one per AZ)"
  type        = list(string)
  default     = ["10.0.20.0/24", "10.0.21.0/24"]
}

variable "single_nat_gateway" {
  description = "Use a single shared NAT Gateway instead of one per AZ (cheaper, less resilient)"
  type        = bool
  default     = true
}

# ---------------------------------------------------------------------------
# ECS / Application
# ---------------------------------------------------------------------------

variable "container_port" {
  description = "Port the API container listens on"
  type        = number
  default     = 8080
}

variable "api_image" {
  description = "Container image for the public API service. Defaults to a public placeholder; point this at the api ECR repo URI once you've pushed a real image."
  type        = string
  default     = "public.ecr.aws/nginx/nginx:latest"
}

variable "worker_image" {
  description = "Container image for the background worker service. Defaults to a public placeholder; point this at the worker ECR repo URI once you've pushed a real image."
  type        = string
  default     = "public.ecr.aws/docker/library/busybox:latest"
}

variable "task_cpu" {
  description = "Fargate task CPU units, used by both the api and worker task definitions"
  type        = number
  default     = 256
}

variable "task_memory" {
  description = "Fargate task memory (MiB), used by both the api and worker task definitions"
  type        = number
  default     = 512
}

variable "api_desired_count" {
  description = "Number of API service tasks to run"
  type        = number
  default     = 2
}

variable "worker_desired_count" {
  description = "Number of worker service tasks to run"
  type        = number
  default     = 1
}

variable "health_check_path" {
  description = "HTTP path the ALB target group uses for health checks against the API service"
  type        = string
  default     = "/"
}

# ---------------------------------------------------------------------------
# RDS
# ---------------------------------------------------------------------------

variable "db_engine_version" {
  description = "PostgreSQL engine version"
  type        = string
  default     = "16.4"
}

variable "db_instance_class" {
  description = "RDS instance class"
  type        = string
  default     = "db.t3.micro"
}

variable "db_allocated_storage" {
  description = "Allocated storage for RDS, in GB"
  type        = number
  default     = 20
}

variable "db_name" {
  description = "Initial database name"
  type        = string
  default     = "appdb"
}

variable "db_username" {
  description = "Master username for RDS"
  type        = string
  default     = "app_admin"
}

variable "db_multi_az" {
  description = "Whether to deploy RDS in Multi-AZ mode"
  type        = bool
  default     = false
}

variable "db_skip_final_snapshot" {
  description = "Skip final snapshot on destroy (set false for real environments)"
  type        = bool
  default     = true
}
