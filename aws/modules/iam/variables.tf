variable "project_name" {
  type        = string
  description = "Project name"
}

variable "environment" {
  type        = string
  description = "Environment name"
}

variable "bucket_arn" {
  type        = string
  description = "S3 bucket ARN for Lake Formation registration"
}

variable "glue_database_name" {
  type        = string
  description = "Glue database name for permissions"
}

variable "table_templates" {
  type        = any
  description = "Map of table templates from YAML"
}

variable "restricted_columns" {
  type        = map(list(string))
  description = "Map of table name to list of restricted column names"
}

variable "lake_formation_admins" {
  type        = list(string)
  description = "List of IAM principal ARNs for Lake Formation admin"
  default     = []
}
