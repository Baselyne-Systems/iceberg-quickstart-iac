variable "project_name" {
  type        = string
  description = "Project name"
}

variable "environment" {
  type        = string
  description = "Environment name"
}

variable "gcp_location" {
  type        = string
  description = "BigQuery dataset location"
}

variable "bucket_name" {
  type        = string
  description = "GCS bucket name"
}

variable "table_templates" {
  type        = any
  description = "Map of table templates from YAML"
}
