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

variable "nessie_internal" {
  type        = bool
  description = "Whether the ALB should be internal (not internet-facing)"
  default     = true
}

variable "nessie_allowed_cidrs" {
  type        = list(string)
  description = "CIDR blocks allowed to access the Nessie ALB"
  default     = ["10.0.0.0/8"]
}

variable "certificate_arn" {
  type        = string
  description = "ACM certificate ARN for HTTPS. Leave empty for HTTP-only."
  default     = ""
}

variable "alb_access_log_bucket" {
  type        = string
  description = "S3 bucket name for ALB access logs. Leave empty to disable."
  default     = ""
}

variable "alarm_sns_topic_arn" {
  type        = string
  description = "SNS topic ARN for CloudWatch alarms. Leave empty to disable notifications."
  default     = ""
}
