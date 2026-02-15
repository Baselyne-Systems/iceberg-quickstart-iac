variable "project_name" {
  type        = string
  description = "Project name used for resource naming and tagging"
}

variable "environment" {
  type        = string
  description = "Environment name (dev, staging, prod)"
  default     = "dev"
}

variable "gcp_project_id" {
  type        = string
  description = "GCP project ID"
}

variable "gcp_region" {
  type        = string
  description = "GCP region for all resources"
  default     = "us-central1"
}

variable "gcp_location" {
  type        = string
  description = "GCP multi-region location for BigQuery dataset (US, EU)"
  default     = "US"
}
