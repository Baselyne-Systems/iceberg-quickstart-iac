# ── Prod Environment ───────────────────────────────────────────
# Hardened settings for production workloads.
# Use with: terraform plan -var-file=../environments/prod.tfvars

# ── Core ───────────────────────────────────────────────────────
project_name = "lakehouse"
environment  = "prod"
aws_region   = "us-east-1"
catalog_type = "glue"    # or "nessie"

# ── Nessie Compute (if catalog_type = "nessie") ──────────────
# Scaled up with HA — minimum 2 tasks across AZs
nessie_cpu       = 1024
nessie_memory    = 2048
nessie_min_count = 2
nessie_max_count = 6

# ── Networking (if catalog_type = "nessie") ──────────────────
nessie_internal      = true
nessie_allowed_cidrs = ["10.0.0.0/8"]
# HTTPS — replace with your ACM certificate ARN
certificate_arn = "arn:aws:acm:us-east-1:123456789012:certificate/your-cert-id"

# ── Monitoring ─────────────────────────────────────────────────
# Replace with your SNS topic ARN
alarm_sns_topic_arn = "arn:aws:sns:us-east-1:123456789012:lakehouse-alarms"

# ── Compliance ─────────────────────────────────────────────────
enable_cloudtrail  = true
log_retention_days = 365    # SOC2 minimum; use 2190 for HIPAA

# ── Logging ──────────────────────────────────────────────────
# Replace with your log bucket names
access_log_bucket     = "my-company-s3-access-logs"
alb_access_log_bucket = "my-company-alb-access-logs"
