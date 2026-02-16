# ── Dev Environment ────────────────────────────────────────────
# Minimal settings for development and testing.
# Use with: terraform plan -var-file=../environments/dev.tfvars

# ── Core ───────────────────────────────────────────────────────
project_name = "lakehouse"
environment  = "dev"
aws_region   = "us-east-1"
catalog_type = "glue"    # or "nessie"

# ── Nessie Compute (if catalog_type = "nessie") ──────────────
# Smallest Fargate task — single instance, no HA
nessie_cpu       = 256
nessie_memory    = 512
nessie_min_count = 1
nessie_max_count = 2

# ── Networking (if catalog_type = "nessie") ──────────────────
# HTTP only — no certificate needed for dev
nessie_internal = true
certificate_arn = ""

# ── Compliance ─────────────────────────────────────────────────
# Relaxed for dev — shorter retention, no CloudTrail
enable_cloudtrail  = false
log_retention_days = 30

# ── Logging (optional) ──────────────────────────────────────
# access_log_bucket     = ""
# alb_access_log_bucket = ""
