# Configuration Reference

Complete reference for every configurable setting in this project — Terraform variables, Dagster environment variables, and example configurations.

---

## Terraform Variables (AWS)

All variables are set in a `.tfvars` file. See `examples/` for ready-to-use configurations.

### Core Variables

These are the primary settings every deployment needs.

| Variable | Type | Default | Required | Description |
|----------|------|---------|----------|-------------|
| `project_name` | string | — | **Yes** | Project name used in all resource names and tags. Must be 2-21 lowercase alphanumeric characters or hyphens, starting with a letter. Example: `"lakehouse"`, `"mycompany-data"` |
| `environment` | string | `"dev"` | No | Environment label: `dev`, `staging`, or `prod`. Used in resource names (e.g., `lakehouse-prod-nessie`). |
| `aws_region` | string | `"us-east-1"` | No | AWS region for all resources. |
| `catalog_type` | string | `"glue"` | No | Iceberg catalog backend: `"glue"` (serverless, simplest) or `"nessie"` (Git-like branching, requires VPC). |

### Nessie-Specific Variables

Only relevant when `catalog_type = "nessie"`.

| Variable | Type | Default | Required | Description |
|----------|------|---------|----------|-------------|
| `nessie_image_tag` | string | `"0.99.0"` | No | Pinned Nessie Docker image version. We recommend pinning rather than using `latest` — see [Architecture: Why pin the Nessie image tag?](architecture.md#why-pin-the-nessie-image-tag) |
| `vpc_cidr` | string | `"10.0.0.0/16"` | No | CIDR block for the VPC created for Nessie. Change this if `10.0.0.0/16` conflicts with your existing network (e.g., if you're peering VPCs). |

### Nessie Networking

Control how the Nessie ALB is exposed.

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `nessie_internal` | bool | `true` | When `true`, the ALB is internal (only reachable from within the VPC or peered networks). Set to `false` for internet-facing access — **not recommended for production**. |
| `nessie_allowed_cidrs` | list(string) | `["10.0.0.0/8"]` | CIDR blocks allowed to reach the ALB on ports 80/443. For internal ALBs, this is typically your corporate network or VPC CIDRs. For internet-facing ALBs, use `["0.0.0.0/0"]` (but prefer internal + VPN instead). |
| `certificate_arn` | string | `""` | ACM certificate ARN to enable HTTPS on port 443. When set, port 80 automatically redirects to 443. Leave empty for HTTP-only (acceptable for internal ALBs in dev). |

**How HTTPS works:**
- Empty `certificate_arn` → ALB listens on port 80 (HTTP) only
- Set `certificate_arn` → ALB listens on port 443 (HTTPS) with TLS 1.3. Port 80 returns a 301 redirect to HTTPS.

**How to get a certificate:**
```bash
# Request a certificate (DNS validation is recommended)
aws acm request-certificate \
  --domain-name nessie.internal.yourcompany.com \
  --validation-method DNS

# ACM will output the certificate ARN — use that value for certificate_arn
```

### Nessie Compute

Size the Fargate tasks running Nessie.

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `nessie_cpu` | number | `512` | Fargate CPU units. Valid values: `256`, `512`, `1024`, `2048`, `4096`. See [Fargate pricing](https://aws.amazon.com/fargate/pricing/) for cost impact. |
| `nessie_memory` | number | `1024` | Fargate memory in MiB. Must be compatible with the chosen CPU — see [task size combinations](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/task_definition_parameters.html#task_size). |
| `nessie_min_count` | number | `1` | Auto-scaling floor. Set to `2` in production for high availability (tasks run across AZs). |
| `nessie_max_count` | number | `3` | Auto-scaling ceiling. Auto-scaling triggers at 70% average CPU utilization. |

**Sizing guidance:**

| Workload | CPU | Memory | Min | Max | Estimated monthly cost |
|----------|-----|--------|-----|-----|----------------------|
| Dev/testing | 256 | 512 | 1 | 1 | ~$10 |
| Small team (< 10 users) | 512 | 1024 | 1 | 3 | ~$25-75 |
| Production | 1024 | 2048 | 2 | 6 | ~$60-200 |
| High throughput | 2048 | 4096 | 2 | 10 | ~$120-600 |

### Governance

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `lake_formation_admins` | list(string) | `[]` | IAM principal ARNs to grant Lake Formation admin. Only used with `catalog_type = "glue"`. Example: `["arn:aws:iam::123456789012:role/DataAdmin"]` |

### Monitoring

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `alarm_sns_topic_arn` | string | `""` | SNS topic ARN for CloudWatch alarms. When set, Nessie health-check and scaling alarms notify this topic. Leave empty to create alarms without notifications. |

**Setting up SNS alerts:**
```bash
# Create the topic
aws sns create-topic --name lakehouse-alarms
# → outputs TopicArn

# Subscribe your email
aws sns subscribe \
  --topic-arn arn:aws:sns:us-east-1:123456789012:lakehouse-alarms \
  --protocol email \
  --notification-endpoint ops-team@yourcompany.com

# Confirm the subscription via the email you receive
```

You can also subscribe PagerDuty, Slack (via Lambda), or any HTTPS endpoint.

### Compliance

Controls for SOC2 and HIPAA compliance. See the [Compliance Guide](compliance.md) for details.

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `enable_cloudtrail` | bool | `true` | Enable CloudTrail S3 data-event logging. Creates a trail + audit bucket with 7-year retention. Required for SOC2 CC7.2 and HIPAA §164.312(b). |
| `log_retention_days` | number | `365` | CloudWatch log group retention in days. SOC2 requires >= 365 days. HIPAA requires >= 2190 days (6 years). |

### Logging

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `access_log_bucket` | string | `""` | S3 bucket name for data bucket server access logs. The target bucket must exist and have the [correct bucket policy](https://docs.aws.amazon.com/AmazonS3/latest/userguide/enable-server-access-logging.html). Leave empty to disable. |
| `alb_access_log_bucket` | string | `""` | S3 bucket name for ALB access logs. Must be in the same region and have the [ELB service principal policy](https://docs.aws.amazon.com/elasticloadbalancing/latest/application/enable-access-logging.html). Leave empty to disable. |

**Why enable access logging?**
- **S3 access logs**: Audit trail of who accessed your data files — useful for compliance (SOC2, HIPAA)
- **ALB access logs**: See every request to the Nessie API — useful for debugging and security monitoring

---

## Terraform Variables (GCP)

### Core Variables

| Variable | Type | Default | Required | Description |
|----------|------|---------|----------|-------------|
| `project_name` | string | — | **Yes** | Project name used in all resource names and labels. Same constraints as AWS. |
| `environment` | string | `"dev"` | No | Environment label: `dev`, `staging`, or `prod`. |
| `gcp_project_id` | string | — | **Yes** | GCP project ID (e.g., `my-project-123`). |
| `gcp_region` | string | `"us-central1"` | No | GCP region for regional resources. |
| `gcp_location` | string | `"US"` | No | Multi-region location for GCS bucket and BigQuery dataset. |

### Compliance

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `enable_cmek` | bool | `true` | Enable customer-managed encryption keys (CMEK) for the GCS bucket. Creates a KMS key ring and crypto key with 90-day rotation. Required for SOC2 CC6.7 and HIPAA §164.312(c)(1). |
| `enable_audit_logging` | bool | `true` | Enable audit log sink for GCS data access events. Creates a dedicated audit bucket with 7-year retention. Required for SOC2 CC7.2 and HIPAA §164.312(b). |

---

## Dagster Environment Variables

All environment variables read by the Dagster Python code. Set these in your shell, a `.env` file (see `dagster/.env.example`), or in `docker-compose.yaml`.

### Catalog Backend

| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| `LAKEHOUSE_BACKEND` | **Yes** | `aws-glue` | Which catalog to connect to. Values: `aws-glue`, `aws-nessie`, `gcp`. |

### AWS Settings

| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| `AWS_REGION` | No | `us-east-1` | AWS region for S3 and Glue API calls. |
| `AWS_PROFILE` | No | `default` | AWS CLI profile for credentials. |

### Nessie Settings

Required when `LAKEHOUSE_BACKEND=aws-nessie`.

| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| `NESSIE_URI` | **Yes** (for nessie) | — | Nessie REST API endpoint. Get this from `terraform output nessie_endpoint`. Example: `http://lakehouse-prod-nessie-1234.us-east-1.elb.amazonaws.com/api/v2` |

### GCP Settings

Required when `LAKEHOUSE_BACKEND=gcp`.

| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| `ICEBERG_REST_URI` | **Yes** (for gcp) | `""` | Iceberg REST catalog endpoint. |
| `GCP_PROJECT_ID` | **Yes** (for gcp) | `""` | GCP project ID (e.g., `my-project-123`). |

### Source Asset Credentials

Source assets (auto-generated from `source` blocks in YAML templates) read files from S3 or GCS using the **same AWS/GCP credentials** configured for the IO manager above. No additional environment variables are needed. PyArrow's built-in S3 and GCS filesystem layers use the standard credential chain (AWS CLI profile, instance role, `GOOGLE_APPLICATION_CREDENTIALS`, etc.).

### Access Control

| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| `LAKEHOUSE_ACCESS_LEVEL` | No | `admin` | Controls PII column visibility in Dagster assets. Values: `admin` (see all columns), `writer` (see all columns), `reader` (columns marked `access_level: restricted` in table templates are masked). |

### Alerting

| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| `ALERT_SNS_TOPIC_ARN` | No | — | SNS topic ARN for alerts from the schema-drift sensor and quality checks. Requires AWS credentials with `sns:Publish` permission. |
| `ALERT_SLACK_WEBHOOK_URL` | No | — | Slack incoming webhook URL for alerts. Can be used alongside or instead of SNS. Create one at: Slack workspace settings → Apps → Incoming Webhooks. |

---

## Example Configurations

### Quick Start — AWS Glue (Simplest)

**Use case:** First-time setup, evaluation, small team, no servers to manage.

```bash
cp examples/aws-glue-quickstart.tfvars aws/terraform.tfvars
# Edit: change project_name to yours
cd aws && terraform init && terraform plan
```

What you get: S3 bucket + Glue catalog + Athena workgroup + IAM roles. No VPC, no running containers, minimal cost.

### Quick Start — AWS Nessie (Git-like Branching)

**Use case:** Teams that need data branching for experimentation.

```bash
cp examples/aws-nessie-quickstart.tfvars aws/terraform.tfvars
# Edit: change project_name, optionally adjust vpc_cidr
cd aws && terraform init && terraform plan
```

What you get: Everything above, plus a VPC + Nessie on Fargate + ALB. HTTP-only, internal ALB, single task.

### Production — AWS Nessie (Hardened)

**Use case:** Production deployment with HTTPS, monitoring, logging, and high availability.

```bash
cp examples/aws-nessie-production.tfvars aws/terraform.tfvars
# Edit: fill in your actual certificate_arn, SNS topic, and log buckets
cd aws && terraform init && terraform plan
```

What you get: HTTPS with TLS 1.3, internal ALB, 2-6 auto-scaled tasks, CloudWatch alarms → SNS, S3 + ALB access logging.

**Prerequisites for production:**
1. An ACM certificate (see [Nessie Networking](#nessie-networking) above)
2. An SNS topic with subscriptions (see [Monitoring](#monitoring) above)
3. S3 buckets for access logs with the correct bucket policies
4. A VPN or Direct Connect if the ALB is internal

### Dagster — Local Development

```bash
cd dagster
cp .env.example .env
# Edit .env: set LAKEHOUSE_BACKEND and backend-specific vars
source .venv/bin/activate
dagster dev
```

### Dagster — Docker Compose

```bash
cd dagster
cp .env.example .env
# Edit .env with your settings
docker-compose up --build
# Open http://localhost:3000
```

The `docker-compose.yaml` reads `.env` automatically via `env_file: .env`. Environment variables in `docker-compose.yaml` take precedence over `.env` for any duplicates.

---

## Makefile Targets

| Target | Description |
|--------|-------------|
| `make validate` | Run `terraform validate` on both AWS and GCP modules |
| `make fmt` | Auto-format all Terraform files |
| `make plan-aws-glue` | Plan with `examples/aws-glue-quickstart.tfvars` |
| `make plan-aws-nessie` | Plan with `examples/aws-nessie-quickstart.tfvars` |
| `make plan-aws-nessie-prod` | Plan with `examples/aws-nessie-production.tfvars` |
| `make plan-gcp` | Plan with `examples/gcp-quickstart.tfvars` |
| `make dagster-dev` | Install Dagster and start the dev server |
| `make lint` | Run pre-commit hooks on all files |
| `make test` | Run `tests/validate.sh` + Dagster pytest suite |
| `make clean` | Remove `.terraform/` directories and lock files |

---

## Variable Precedence and Overrides

Terraform resolves variable values in this order (last wins):

1. `default` in `variables.tf`
2. `terraform.tfvars` or `*.auto.tfvars` in the working directory
3. `-var-file=<path>` flag (what the Makefile uses)
4. `-var='key=value'` flag
5. `TF_VAR_<name>` environment variable

So you can override any `.tfvars` value on the command line:
```bash
terraform plan \
  -var-file=../examples/aws-nessie-production.tfvars \
  -var='nessie_max_count=10'
```

Or via environment variables:
```bash
export TF_VAR_alarm_sns_topic_arn="arn:aws:sns:us-east-1:123456789012:my-topic"
terraform plan -var-file=../examples/aws-nessie-quickstart.tfvars
```
