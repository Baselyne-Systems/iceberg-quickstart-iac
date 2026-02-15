# ── Core ───────────────────────────────────────────────────────
project_name     = "lakehouse"
environment      = "prod"
aws_region       = "us-east-1"
catalog_type     = "nessie"
nessie_image_tag = "0.99.0"
vpc_cidr         = "10.0.0.0/16"

# ── Networking ─────────────────────────────────────────────────
# Internal ALB — only reachable from within the VPC / peered networks
nessie_internal      = true
nessie_allowed_cidrs = ["10.0.0.0/8"]

# HTTPS with an ACM certificate (get ARN from AWS Certificate Manager)
certificate_arn = "arn:aws:acm:us-east-1:123456789012:certificate/your-cert-id"

# ── Compute ────────────────────────────────────────────────────
# Scaled up for production workloads
nessie_cpu       = 1024
nessie_memory    = 2048
nessie_min_count = 2
nessie_max_count = 6

# ── Monitoring ─────────────────────────────────────────────────
# CloudWatch alarms notify this SNS topic (subscribe your email/PagerDuty)
alarm_sns_topic_arn = "arn:aws:sns:us-east-1:123456789012:lakehouse-alarms"

# ── Logging ────────────────────────────────────────────────────
# S3 data bucket access logs
access_log_bucket = "my-company-s3-access-logs"

# ALB access logs (must be in the same region, with the correct bucket policy)
alb_access_log_bucket = "my-company-alb-access-logs"
