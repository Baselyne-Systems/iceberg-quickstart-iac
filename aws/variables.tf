variable "project_name" {
  type        = string
  description = "Project name used for resource naming and tagging"
}

variable "environment" {
  type        = string
  description = "Environment name (dev, staging, prod)"
  default     = "dev"
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
}

variable "lake_formation_admins" {
  type        = list(string)
  description = "List of IAM principal ARNs to grant Lake Formation admin"
  default     = []
}
