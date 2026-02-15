output "lakehouse_bucket_name" {
  description = "S3 bucket name for Iceberg data"
  value       = module.storage.bucket_name
}

output "lakehouse_bucket_arn" {
  description = "S3 bucket ARN"
  value       = module.storage.bucket_arn
}

output "catalog_type" {
  description = "Active catalog type"
  value       = var.catalog_type
}

output "glue_database_name" {
  description = "Glue database name (empty if catalog_type != glue)"
  value       = var.catalog_type == "glue" ? module.catalog_glue[0].database_name : ""
}

output "nessie_endpoint" {
  description = "Nessie API endpoint (empty if catalog_type != nessie)"
  value       = var.catalog_type == "nessie" ? module.catalog_nessie[0].nessie_endpoint : ""
}

output "athena_workgroup" {
  description = "Athena workgroup name"
  value       = var.catalog_type == "glue" ? module.athena[0].workgroup_name : ""
}
