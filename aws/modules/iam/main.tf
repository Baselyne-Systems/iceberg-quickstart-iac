# Lake Formation admin setup
resource "aws_lakeformation_data_lake_settings" "lakehouse" {
  admins = var.lake_formation_admins
}

# Register the S3 bucket as a Lake Formation resource
resource "aws_lakeformation_resource" "lakehouse" {
  arn      = var.bucket_arn
  role_arn = aws_iam_role.lakeformation.arn
}

# Lake Formation service role
resource "aws_iam_role" "lakeformation" {
  name = "${var.project_name}-${var.environment}-lakeformation"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "lakeformation.amazonaws.com"
      }
    }]
  })
}

resource "aws_iam_role_policy" "lakeformation_s3" {
  name = "lakeformation-s3-access"
  role = aws_iam_role.lakeformation.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject",
          "s3:ListBucket",
          "s3:GetBucketLocation",
        ]
        Resource = [
          var.bucket_arn,
          "${var.bucket_arn}/*",
        ]
      }
    ]
  })
}

# --- Reader role: all columns except restricted ---

resource "aws_iam_role" "reader" {
  name = "${var.project_name}-${var.environment}-lakehouse-reader"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
      }
    }]
  })

  tags = {
    Name = "${var.project_name}-${var.environment}-lakehouse-reader"
  }
}

# Grant reader SELECT on all columns except restricted ones
resource "aws_lakeformation_permissions" "reader_tables" {
  for_each = var.table_templates

  principal   = aws_iam_role.reader.arn
  permissions = ["SELECT"]

  table_with_columns {
    database_name = var.glue_database_name
    name          = each.value.name

    excluded_column_names = try(var.restricted_columns[each.key], [])
  }

  lifecycle {
    ignore_changes = [table_with_columns]
  }
}

# --- Writer role: all columns ---

resource "aws_iam_role" "writer" {
  name = "${var.project_name}-${var.environment}-lakehouse-writer"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
      }
    }]
  })
}

resource "aws_lakeformation_permissions" "writer_tables" {
  for_each = var.table_templates

  principal   = aws_iam_role.writer.arn
  permissions = ["SELECT", "INSERT", "DELETE"]

  table_with_columns {
    database_name = var.glue_database_name
    name          = each.value.name
    wildcard      = true
  }

  lifecycle {
    ignore_changes = [table_with_columns]
  }
}

# --- Admin role: all permissions including ALTER ---

resource "aws_iam_role" "admin" {
  name = "${var.project_name}-${var.environment}-lakehouse-admin"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
      }
    }]
  })
}

resource "aws_lakeformation_permissions" "admin_database" {
  principal   = aws_iam_role.admin.arn
  permissions = ["ALL"]

  database {
    name = var.glue_database_name
  }
}

data "aws_caller_identity" "current" {}
