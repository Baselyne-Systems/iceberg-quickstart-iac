resource "google_bigquery_dataset" "lakehouse" {
  dataset_id    = "${replace(var.project_name, "-", "_")}_${var.environment}"
  friendly_name = "${var.project_name} ${var.environment} Lakehouse"
  description   = "Iceberg lakehouse dataset"
  location      = var.gcp_location

  labels = {
    project     = var.project_name
    environment = var.environment
    managed-by  = "terraform"
  }

  lifecycle {
    prevent_destroy = true
  }
}

# BigLake connection for accessing Iceberg data in GCS
resource "google_bigquery_connection" "lakehouse" {
  provider      = google-beta
  connection_id = "${var.project_name}-${var.environment}-lakehouse"
  location      = var.gcp_location
  friendly_name = "Lakehouse BigLake Connection"

  cloud_resource {}
}

# Grant the BigLake connection's service account access to GCS
resource "google_storage_bucket_iam_member" "biglake_reader" {
  bucket = var.bucket_name
  role   = "roles/storage.objectViewer"
  member = "serviceAccount:${google_bigquery_connection.lakehouse.cloud_resource[0].service_account_id}"
}

# External Iceberg tables created via BigQuery job DDL
# google_bigquery_table doesn't support managed Iceberg tables directly
resource "google_bigquery_job" "create_iceberg_table" {
  for_each = var.table_templates

  job_id   = "create-${each.value.name}-${md5(local.create_table_ddl[each.key])}"
  location = var.gcp_location

  query {
    query              = local.create_table_ddl[each.key]
    create_disposition = "CREATE_IF_NEEDED"
    use_legacy_sql     = false
  }

  lifecycle {
    ignore_changes = [job_id]
  }
}

locals {
  iceberg_to_bq_type = {
    "boolean"     = "BOOL"
    "int"         = "INT64"
    "long"        = "INT64"
    "float"       = "FLOAT64"
    "double"      = "FLOAT64"
    "date"        = "DATE"
    "time"        = "TIME"
    "timestamp"   = "TIMESTAMP"
    "timestamptz" = "TIMESTAMP"
    "string"      = "STRING"
    "uuid"        = "STRING"
    "binary"      = "BYTES"
  }

  create_table_ddl = {
    for k, tbl in var.table_templates : k => <<-EOT
      CREATE EXTERNAL TABLE IF NOT EXISTS `${google_bigquery_dataset.lakehouse.dataset_id}.${tbl.name}` (
        ${join(",\n        ", [for col in tbl.columns : "${col.name} ${local.iceberg_to_bq_type[col.type]}"])}
      )
      WITH CONNECTION `${google_bigquery_connection.lakehouse.name}`
      OPTIONS (
        format = 'ICEBERG',
        uris = ['gs://${var.bucket_name}/${tbl.namespace}/${tbl.name}/metadata/']
      )
    EOT
  }
}
