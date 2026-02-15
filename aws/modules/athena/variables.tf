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
  description = "S3 bucket name for query results"
}

variable "glue_database_name" {
  type        = string
  description = "Glue database name for named queries"
}

variable "table_templates" {
  type        = any
  description = "Map of table templates from YAML"
}
