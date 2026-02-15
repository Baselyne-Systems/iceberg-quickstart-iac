variable "project_name" {
  type        = string
  description = "Project name used for resource naming and tagging"

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,20}$", var.project_name))
    error_message = "project_name must be 2-21 lowercase alphanumeric characters or hyphens, starting with a letter."
  }
}

variable "environment" {
  type        = string
  description = "Environment name (dev, staging, prod)"
  default     = "dev"

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "environment must be one of: dev, staging, prod."
  }
}

variable "aws_region" {
  type        = string
  description = "AWS region for all resources"
  default     = "us-east-1"
}

variable "catalog_type" {
  type        = string
  description = "Iceberg catalog backend: glue or nessie"
  default     = "glue"

  validation {
    condition     = contains(["glue", "nessie"], var.catalog_type)
    error_message = "catalog_type must be either 'glue' or 'nessie'."
  }
}

variable "nessie_image_tag" {
  type        = string
  description = "Nessie server Docker image tag (pinned version)"
  default     = "0.99.0"
}

variable "vpc_cidr" {
  type        = string
  description = "CIDR block for VPC (only used when catalog_type = nessie)"
  default     = "10.0.0.0/16"

  validation {
    condition     = can(cidrhost(var.vpc_cidr, 0))
    error_message = "vpc_cidr must be a valid CIDR block (e.g. 10.0.0.0/16)."
  }
}

variable "lake_formation_admins" {
  type        = list(string)
  description = "List of IAM principal ARNs to grant Lake Formation admin"
  default     = []
}

# ── Nessie Networking ──────────────────────────────────────────

variable "nessie_internal" {
  type        = bool
  description = "Whether the Nessie ALB should be internal (not internet-facing)"
  default     = true
}

variable "nessie_allowed_cidrs" {
  type        = list(string)
  description = "CIDR blocks allowed to access the Nessie ALB"
  default     = ["10.0.0.0/8"]
}

variable "certificate_arn" {
  type        = string
  description = "ACM certificate ARN for HTTPS on the Nessie ALB. Leave empty for HTTP-only."
  default     = ""
}

# ── Nessie Compute ─────────────────────────────────────────────

variable "nessie_cpu" {
  type        = number
  description = "Fargate CPU units for Nessie tasks (256, 512, 1024, 2048, 4096)"
  default     = 512
}

variable "nessie_memory" {
  type        = number
  description = "Fargate memory (MiB) for Nessie tasks"
  default     = 1024
}

variable "nessie_min_count" {
  type        = number
  description = "Minimum number of Nessie ECS tasks (auto-scaling floor)"
  default     = 1
}

variable "nessie_max_count" {
  type        = number
  description = "Maximum number of Nessie ECS tasks (auto-scaling ceiling)"
  default     = 3
}

# ── Monitoring ─────────────────────────────────────────────────

variable "alarm_sns_topic_arn" {
  type        = string
  description = "SNS topic ARN for CloudWatch alarms. Leave empty to disable notifications."
  default     = ""
}

# ── Compliance ─────────────────────────────────────────────────

variable "enable_cloudtrail" {
  type        = bool
  description = "Enable CloudTrail S3 data-event logging for compliance (SOC2/HIPAA)"
  default     = true
}

variable "log_retention_days" {
  type        = number
  description = "CloudWatch log group retention in days (SOC2 requires 365, HIPAA requires 2190)"
  default     = 365
}

# ── Logging ────────────────────────────────────────────────────

variable "access_log_bucket" {
  type        = string
  description = "S3 bucket name for data bucket access logging. Leave empty to disable."
  default     = ""
}

variable "alb_access_log_bucket" {
  type        = string
  description = "S3 bucket name for ALB access logs. Leave empty to disable."
  default     = ""
}
