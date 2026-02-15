output "reader_role_arn" {
  description = "Lakehouse reader role ARN"
  value       = aws_iam_role.reader.arn
}

output "writer_role_arn" {
  description = "Lakehouse writer role ARN"
  value       = aws_iam_role.writer.arn
}

output "admin_role_arn" {
  description = "Lakehouse admin role ARN"
  value       = aws_iam_role.admin.arn
}
