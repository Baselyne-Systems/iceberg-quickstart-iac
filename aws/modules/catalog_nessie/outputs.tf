output "nessie_endpoint" {
  description = "Nessie API endpoint URL"
  value       = "http://${aws_lb.nessie.dns_name}/api/v2"
}

output "ecs_cluster_name" {
  description = "ECS cluster name"
  value       = aws_ecs_cluster.nessie.name
}

output "dynamodb_table_name" {
  description = "DynamoDB table name for Nessie version store"
  value       = aws_dynamodb_table.nessie.name
}
