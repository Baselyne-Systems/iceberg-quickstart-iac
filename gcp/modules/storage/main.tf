resource "google_storage_bucket" "lakehouse" {
  name          = "${var.project_name}-${var.environment}-lakehouse"
  location      = var.gcp_location
  force_destroy = false

  uniform_bucket_level_access = true

  versioning {
    enabled = true
  }

  lifecycle_rule {
    condition {
      age = 90
    }
    action {
      type          = "SetStorageClass"
      storage_class = "NEARLINE"
    }
  }

  lifecycle_rule {
    condition {
      age                = 30
      with_state         = "ARCHIVED"
      num_newer_versions = 1
    }
    action {
      type = "Delete"
    }
  }

  lifecycle_rule {
    condition {
      age = 7
    }
    action {
      type = "AbortIncompleteMultipartUpload"
    }
  }

  dynamic "encryption" {
    for_each = var.enable_cmek ? [1] : []
    content {
      default_kms_key_name = google_kms_crypto_key.lakehouse[0].id
    }
  }

  labels = {
    project     = var.project_name
    environment = var.environment
    managed-by  = "terraform"
  }

  lifecycle {
    prevent_destroy = true
  }

  depends_on = [google_project_iam_member.gcs_kms]
}

# --- CMEK Encryption (SOC2 / HIPAA) ---

resource "google_kms_key_ring" "lakehouse" {
  count    = var.enable_cmek ? 1 : 0
  name     = "${var.project_name}-${var.environment}-lakehouse"
  location = var.gcp_location

  lifecycle {
    prevent_destroy = true
  }
}

resource "google_kms_crypto_key" "lakehouse" {
  count           = var.enable_cmek ? 1 : 0
  name            = "${var.project_name}-${var.environment}-lakehouse"
  key_ring        = google_kms_key_ring.lakehouse[0].id
  rotation_period = "7776000s" # 90 days

  lifecycle {
    prevent_destroy = true
  }
}

data "google_storage_project_service_account" "gcs" {
  count = var.enable_cmek ? 1 : 0
}

resource "google_project_iam_member" "gcs_kms" {
  count   = var.enable_cmek ? 1 : 0
  project = var.gcp_project_id
  role    = "roles/cloudkms.cryptoKeyEncrypterDecrypter"
  member  = "serviceAccount:${data.google_storage_project_service_account.gcs[0].email_address}"
}
