# --- Audit Log Sink: Data Access Logging (SOC2 / HIPAA) ---

resource "google_storage_bucket" "audit_logs" {
  count         = var.enable_audit_logging ? 1 : 0
  name          = "${var.project_name}-${var.environment}-audit-logs"
  location      = var.gcp_location
  force_destroy = false

  uniform_bucket_level_access = true

  versioning {
    enabled = true
  }

  lifecycle_rule {
    condition {
      age = 365
    }
    action {
      type          = "SetStorageClass"
      storage_class = "COLDLINE"
    }
  }

  lifecycle_rule {
    condition {
      age = 2555 # ~7 years — exceeds HIPAA 6-year requirement
    }
    action {
      type = "Delete"
    }
  }

  labels = {
    project     = var.project_name
    environment = var.environment
    purpose     = "audit-logs"
    managed-by  = "terraform"
  }
}

resource "google_logging_project_sink" "data_access" {
  count                  = var.enable_audit_logging ? 1 : 0
  name                   = "${var.project_name}-${var.environment}-data-access-sink"
  destination            = "storage.googleapis.com/${google_storage_bucket.audit_logs[0].name}"
  filter                 = "logName=\"projects/${var.gcp_project_id}/logs/cloudaudit.googleapis.com%2Fdata_access\" AND resource.type=\"gcs_bucket\" AND resource.labels.bucket_name=\"${google_storage_bucket.lakehouse.name}\""
  unique_writer_identity = true
}

resource "google_project_iam_member" "audit_sink_writer" {
  count   = var.enable_audit_logging ? 1 : 0
  project = var.gcp_project_id
  role    = "roles/storage.objectCreator"
  member  = google_logging_project_sink.data_access[0].writer_identity
}
