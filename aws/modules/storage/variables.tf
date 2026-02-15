variable "project_name" {
  type        = string
  description = "Project name for bucket naming"
}

variable "environment" {
  type        = string
  description = "Environment name"
}

variable "access_log_bucket" {
  type        = string
  description = "S3 bucket name for access logging. Leave empty to disable."
  default     = ""
}

variable "enable_cloudtrail" {
  type        = bool
  description = "Enable CloudTrail S3 data-event logging for compliance (SOC2/HIPAA)"
  default     = true
}
