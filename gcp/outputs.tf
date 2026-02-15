output "lakehouse_bucket_name" {
  description = "GCS bucket name for Iceberg data"
  value       = module.storage.bucket_name
}

output "lakehouse_bucket_url" {
  description = "GCS bucket URL"
  value       = module.storage.bucket_url
}

output "bigquery_dataset_id" {
  description = "BigQuery dataset ID"
  value       = module.biglake.dataset_id
}

output "biglake_connection_id" {
  description = "BigLake connection ID"
  value       = module.biglake.connection_id
}
