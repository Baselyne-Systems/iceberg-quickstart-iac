variable "project_name" {
  type        = string
  description = "Project name for bucket naming"
}

variable "environment" {
  type        = string
  description = "Environment name"
}

variable "gcp_location" {
  type        = string
  description = "GCS bucket location"
}
