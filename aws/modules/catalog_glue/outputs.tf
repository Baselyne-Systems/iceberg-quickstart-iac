output "database_name" {
  description = "Glue catalog database name"
  value       = aws_glue_catalog_database.lakehouse.name
}

output "database_arn" {
  description = "Glue catalog database ARN"
  value       = aws_glue_catalog_database.lakehouse.arn
}

output "table_names" {
  description = "Map of registered table names"
  value       = { for k, v in aws_glue_catalog_table.tables : k => v.name }
}
