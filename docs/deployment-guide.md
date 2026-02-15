# Deployment Guide

## Prerequisites

- Terraform >= 1.5
- AWS CLI configured (for AWS paths) or `gcloud` authenticated (for GCP)
- Python >= 3.10 (for Dagster)
- Docker (optional, for local Dagster dev with docker-compose)

## Step 1: Configure Backend

Copy the backend example and configure your state storage:

```bash
# AWS
cd aws
# Uncomment and configure the backend block in versions.tf

# GCP
cd gcp
# Uncomment and configure the backend block in versions.tf
```

## Step 2: Set Variables

```bash
# AWS with Glue
cd aws
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your values

# Or use an example file:
cp ../examples/aws-glue-quickstart.tfvars terraform.tfvars
```

## Step 3: Deploy Infrastructure

```bash
terraform init
terraform plan
terraform apply
```

## Step 4: Set Up Dagster

```bash
cd dagster
pip install -e ".[dev]"

# Set the backend
export LAKEHOUSE_BACKEND=aws-glue  # or aws-nessie, gcp

# For AWS Nessie, also set:
# export NESSIE_URI=http://<nessie-alb-dns>/api/v2

# For GCP, also set:
# export ICEBERG_REST_URI=<your-iceberg-rest-uri>
# export GCP_PROJECT_ID=<your-project-id>

dagster dev
```

## Step 5: Configure Soda (Optional)

Generate a `configuration.yaml` from Terraform outputs:

```yaml
data_source lakehouse:
  type: duckdb
  # Or configure for your Iceberg catalog:
  # type: spark
  # connection:
  #   catalog: glue_catalog
  #   warehouse: s3://<bucket>/
```

## Step 6: Configure Alerts (Optional)

Set environment variables for alerting:

```bash
# SNS
export ALERT_SNS_TOPIC_ARN=arn:aws:sns:us-east-1:123456789:lakehouse-alerts

# Or Slack
export ALERT_SLACK_WEBHOOK_URL=https://hooks.slack.com/services/...
```

## Verification

```bash
# Validate Terraform
make validate

# Plan (dry run)
make plan-aws-glue    # or plan-aws-nessie, plan-gcp

# Verify Dagster loads
cd dagster && dagster dev
# Check http://localhost:3000 — asset graph should show 3 assets
```

## Tear Down

```bash
cd aws  # or gcp
terraform destroy
```
