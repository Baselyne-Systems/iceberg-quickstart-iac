variable "project_name" {
  type        = string
  description = "Project name"
}

variable "environment" {
  type        = string
  description = "Environment name"
}

variable "bucket_name" {
  type        = string
  description = "S3 bucket name"
}

variable "bucket_arn" {
  type        = string
  description = "S3 bucket ARN"
}

variable "nessie_image_tag" {
  type        = string
  description = "Nessie Docker image tag"
}

variable "vpc_id" {
  type        = string
  description = "VPC ID for Fargate"
}

variable "public_subnets" {
  type        = list(string)
  description = "Public subnet IDs for ALB"
}

variable "private_subnets" {
  type        = list(string)
  description = "Private subnet IDs for Fargate tasks"
}
