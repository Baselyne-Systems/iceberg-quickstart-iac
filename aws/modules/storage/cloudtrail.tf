# --- CloudTrail: S3 data-event auditing (SOC2 / HIPAA) ---

data "aws_caller_identity" "current" {
  count = var.enable_cloudtrail ? 1 : 0
}

data "aws_region" "current" {
  count = var.enable_cloudtrail ? 1 : 0
}

resource "aws_s3_bucket" "audit_trail" {
  count  = var.enable_cloudtrail ? 1 : 0
  bucket = "${var.project_name}-${var.environment}-audit-trail"

  tags = {
    Name    = "${var.project_name}-${var.environment}-audit-trail"
    Purpose = "cloudtrail-audit-logs"
  }
}

resource "aws_s3_bucket_versioning" "audit_trail" {
  count  = var.enable_cloudtrail ? 1 : 0
  bucket = aws_s3_bucket.audit_trail[0].id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "audit_trail" {
  count  = var.enable_cloudtrail ? 1 : 0
  bucket = aws_s3_bucket.audit_trail[0].id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "aws:kms"
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "audit_trail" {
  count  = var.enable_cloudtrail ? 1 : 0
  bucket = aws_s3_bucket.audit_trail[0].id

  rule {
    id     = "audit-log-retention"
    status = "Enabled"
    filter {}

    transition {
      days          = 90
      storage_class = "STANDARD_IA"
    }

    transition {
      days          = 365
      storage_class = "GLACIER"
    }

    expiration {
      days = 2555 # ~7 years — exceeds HIPAA 6-year requirement
    }
  }
}

resource "aws_s3_bucket_public_access_block" "audit_trail" {
  count  = var.enable_cloudtrail ? 1 : 0
  bucket = aws_s3_bucket.audit_trail[0].id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_policy" "audit_trail" {
  count  = var.enable_cloudtrail ? 1 : 0
  bucket = aws_s3_bucket.audit_trail[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "AWSCloudTrailAclCheck"
        Effect    = "Allow"
        Principal = { Service = "cloudtrail.amazonaws.com" }
        Action    = "s3:GetBucketAcl"
        Resource  = aws_s3_bucket.audit_trail[0].arn
      },
      {
        Sid       = "AWSCloudTrailWrite"
        Effect    = "Allow"
        Principal = { Service = "cloudtrail.amazonaws.com" }
        Action    = "s3:PutObject"
        Resource  = "${aws_s3_bucket.audit_trail[0].arn}/AWSLogs/${data.aws_caller_identity.current[0].account_id}/*"
        Condition = {
          StringEquals = {
            "s3:x-amz-acl" = "bucket-owner-full-control"
          }
        }
      },
      {
        Sid       = "DenyInsecureTransport"
        Effect    = "Deny"
        Principal = "*"
        Action    = "s3:*"
        Resource = [
          aws_s3_bucket.audit_trail[0].arn,
          "${aws_s3_bucket.audit_trail[0].arn}/*",
        ]
        Condition = {
          Bool = {
            "aws:SecureTransport" = "false"
          }
        }
      }
    ]
  })

  depends_on = [aws_s3_bucket_public_access_block.audit_trail]
}

resource "aws_cloudtrail" "lakehouse_data_events" {
  count                         = var.enable_cloudtrail ? 1 : 0
  name                          = "${var.project_name}-${var.environment}-data-events"
  s3_bucket_name                = aws_s3_bucket.audit_trail[0].id
  include_global_service_events = false
  is_multi_region_trail         = false
  enable_log_file_validation    = true

  event_selector {
    read_write_type           = "All"
    include_management_events = false

    data_resource {
      type   = "AWS::S3::Object"
      values = ["${aws_s3_bucket.lakehouse.arn}/"]
    }
  }

  tags = {
    Name    = "${var.project_name}-${var.environment}-data-events"
    Purpose = "compliance-audit-trail"
  }

  depends_on = [aws_s3_bucket_policy.audit_trail]
}
