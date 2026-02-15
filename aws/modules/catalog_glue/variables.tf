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
  description = "S3 bucket name for Iceberg data"
}

variable "table_templates" {
  type        = any
  description = "Map of table templates from YAML"
}
