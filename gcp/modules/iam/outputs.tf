output "reader_service_account" {
  description = "Reader service account email"
  value       = google_service_account.reader.email
}

output "writer_service_account" {
  description = "Writer service account email"
  value       = google_service_account.writer.email
}

output "admin_service_account" {
  description = "Admin service account email"
  value       = google_service_account.admin.email
}

output "restricted_policy_tag_id" {
  description = "Data Catalog policy tag ID for restricted columns"
  value       = google_data_catalog_policy_tag.restricted.id
}
