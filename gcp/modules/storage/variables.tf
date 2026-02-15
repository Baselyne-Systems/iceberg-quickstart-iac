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

variable "gcp_project_id" {
  type        = string
  description = "GCP project ID (required for CMEK and audit logging IAM bindings)"
}

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
