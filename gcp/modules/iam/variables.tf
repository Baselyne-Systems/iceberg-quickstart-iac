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
  description = "GCS bucket name"
}

variable "dataset_id" {
  type        = string
  description = "BigQuery dataset ID"
}

variable "restricted_columns" {
  type        = map(list(string))
  description = "Map of table name to list of restricted column names"
}
