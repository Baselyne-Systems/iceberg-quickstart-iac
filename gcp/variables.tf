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

# ── Compliance ─────────────────────────────────────────────────

variable "enable_cmek" {
  type        = bool
  description = "Enable customer-managed encryption keys for GCS bucket (SOC2/HIPAA)"
  default     = true
}

variable "enable_audit_logging" {
  type        = bool
  description = "Enable audit log sink for GCS data access events (SOC2/HIPAA)"
  default     = true
}
