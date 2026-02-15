# ── Core ───────────────────────────────────────────────────────
project_name     = "quickstart"
environment      = "dev"
aws_region       = "us-east-1"
catalog_type     = "nessie"
nessie_image_tag = "0.99.0"
vpc_cidr         = "10.0.0.0/16"

# ── Networking (optional) ─────────────────────────────────────
# nessie_internal      = true
# nessie_allowed_cidrs = ["10.0.0.0/8"]
# certificate_arn      = "arn:aws:acm:us-east-1:123456789012:certificate/abc-123"

# ── Compute (optional) ────────────────────────────────────────
# nessie_cpu       = 512
# nessie_memory    = 1024
# nessie_min_count = 1
# nessie_max_count = 3

# ── Monitoring (optional) ─────────────────────────────────────
# alarm_sns_topic_arn = "arn:aws:sns:us-east-1:123456789012:lakehouse-alarms"

# ── Logging (optional) ────────────────────────────────────────
# access_log_bucket     = "my-s3-access-logs-bucket"
# alb_access_log_bucket = "my-alb-access-logs-bucket"
