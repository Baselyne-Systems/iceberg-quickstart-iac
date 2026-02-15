# --- Service accounts ---

resource "google_service_account" "reader" {
  account_id   = "${var.project_name}-${var.environment}-reader"
  display_name = "Lakehouse Reader"
  description  = "Read-only access to lakehouse (excludes restricted columns)"
}

resource "google_service_account" "writer" {
  account_id   = "${var.project_name}-${var.environment}-writer"
  display_name = "Lakehouse Writer"
  description  = "Read-write access to lakehouse"
}

resource "google_service_account" "admin" {
  account_id   = "${var.project_name}-${var.environment}-admin"
  display_name = "Lakehouse Admin"
  description  = "Full admin access to lakehouse"
}

# --- GCS bucket IAM ---

resource "google_storage_bucket_iam_member" "reader" {
  bucket = var.bucket_name
  role   = "roles/storage.objectViewer"
  member = "serviceAccount:${google_service_account.reader.email}"
}

resource "google_storage_bucket_iam_member" "writer" {
  bucket = var.bucket_name
  role   = "roles/storage.objectUser"
  member = "serviceAccount:${google_service_account.writer.email}"
}

resource "google_storage_bucket_iam_member" "admin" {
  bucket = var.bucket_name
  role   = "roles/storage.admin"
  member = "serviceAccount:${google_service_account.admin.email}"
}

# --- BigQuery dataset IAM ---

resource "google_bigquery_dataset_iam_member" "reader" {
  dataset_id = var.dataset_id
  role       = "roles/bigquery.dataViewer"
  member     = "serviceAccount:${google_service_account.reader.email}"
}

resource "google_bigquery_dataset_iam_member" "writer" {
  dataset_id = var.dataset_id
  role       = "roles/bigquery.dataEditor"
  member     = "serviceAccount:${google_service_account.writer.email}"
}

resource "google_bigquery_dataset_iam_member" "admin" {
  dataset_id = var.dataset_id
  role       = "roles/bigquery.dataOwner"
  member     = "serviceAccount:${google_service_account.admin.email}"
}

# --- Data Catalog policy tags for column-level security ---

resource "google_data_catalog_taxonomy" "lakehouse" {
  provider     = google-beta
  display_name = "${var.project_name}-${var.environment}-column-security"
  description  = "Column-level security taxonomy for lakehouse"

  activated_policy_types = ["FINE_GRAINED_ACCESS_CONTROL"]
}

resource "google_data_catalog_policy_tag" "restricted" {
  provider     = google-beta
  taxonomy     = google_data_catalog_taxonomy.lakehouse.id
  display_name = "Restricted"
  description  = "Restricted columns — PII and sensitive data"
}

resource "google_data_catalog_policy_tag" "internal" {
  provider     = google-beta
  taxonomy     = google_data_catalog_taxonomy.lakehouse.id
  display_name = "Internal"
  description  = "Internal columns — business-sensitive data"
}

# Grant writer and admin access to restricted columns
resource "google_data_catalog_taxonomy_iam_member" "writer_restricted" {
  provider = google-beta
  taxonomy = google_data_catalog_taxonomy.lakehouse.id
  role     = "roles/datacatalog.categoryFineGrainedReader"
  member   = "serviceAccount:${google_service_account.writer.email}"
}

resource "google_data_catalog_taxonomy_iam_member" "admin_restricted" {
  provider = google-beta
  taxonomy = google_data_catalog_taxonomy.lakehouse.id
  role     = "roles/datacatalog.categoryFineGrainedReader"
  member   = "serviceAccount:${google_service_account.admin.email}"
}
