output "dataset_id" {
  description = "BigQuery dataset ID"
  value       = google_bigquery_dataset.lakehouse.dataset_id
}

output "connection_id" {
  description = "BigLake connection ID"
  value       = google_bigquery_connection.lakehouse.connection_id
}

output "connection_service_account" {
  description = "BigLake connection service account"
  value       = google_bigquery_connection.lakehouse.cloud_resource[0].service_account_id
}
