# Deployment Guide

This guide walks through deploying the lakehouse from scratch. Each step includes what the commands do and what to expect.

## Prerequisites

Before you start, make sure these tools are installed:

### Terraform (required)

Terraform reads `.tf` files and creates cloud resources (buckets, databases, IAM roles, etc.). Think of it as a blueprint language for infrastructure.

```bash
# Check if installed
terraform --version    # Should show >= 1.5

# Install (macOS)
brew install terraform

# Install (other platforms): https://developer.hashicorp.com/terraform/install
```

### Cloud CLI (required — pick one based on your cloud)

**AWS CLI** — lets Terraform authenticate to your AWS account:

```bash
# Check if installed
aws --version

# Configure credentials (you'll need an AWS access key)
aws configure
# It will ask for: Access Key ID, Secret Access Key, Region, Output format

# Verify it works
aws sts get-caller-identity    # Should show your account ID
```

**gcloud CLI** — lets Terraform authenticate to your GCP project:

```bash
# Check if installed
gcloud --version

# Log in (opens a browser)
gcloud auth login
gcloud auth application-default login    # Terraform uses this one

# Set your project
gcloud config set project YOUR_PROJECT_ID
```

### Python (required for Dagster pipelines)

```bash
# Check if installed
python3 --version    # Should show >= 3.10 and < 3.14
```

> **Python 3.14 is not yet supported.** Several dependencies (notably `duckdb` used by `soda-core-duckdb`) don't have wheels for 3.14 yet. Use Python 3.10 through 3.13.

### Docker (optional — for running Dagster with docker-compose)

```bash
# Check if installed
docker --version
```

---

## Step 1: Configure the Terraform Backend

Terraform needs to store its **state** — a record of what infrastructure it has created. By default, state is stored locally in a file, but for team usage you should store it remotely (S3 bucket, GCS bucket, or Terraform Cloud).

### Option A: Local State (Quick Start, Single Developer)

No configuration needed — Terraform will create a `terraform.tfstate` file locally. Fine for testing, but don't use this in production (the file can be accidentally deleted or get out of sync with teammates).

### Option B: Remote State on S3 (Recommended for AWS)

1. Create an S3 bucket and DynamoDB table for state locking (do this once, outside of this template):

```bash
# Create the bucket (pick a globally unique name)
aws s3api create-bucket --bucket my-company-tf-state --region us-east-1

# Create a lock table (prevents two people from running Terraform at once)
aws dynamodb create-table \
  --table-name tf-locks \
  --attribute-definitions AttributeName=LockID,AttributeType=S \
  --key-schema AttributeName=LockID,KeyType=HASH \
  --billing-mode PAY_PER_REQUEST
```

2. Open `aws/versions.tf` and uncomment the backend block:

```hcl
terraform {
  backend "s3" {
    bucket         = "my-company-tf-state"     # ← your bucket name
    key            = "iceberg-lakehouse/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "tf-locks"
    encrypt        = true
  }
}
```

### Option C: Remote State on GCS (Recommended for GCP)

1. Create a GCS bucket:

```bash
gsutil mb -l US gs://my-company-tf-state
```

2. Open `gcp/versions.tf` and uncomment the backend block:

```hcl
terraform {
  backend "gcs" {
    bucket = "my-company-tf-state"
    prefix = "iceberg-lakehouse"
  }
}
```

---

## Step 2: Set Your Variables

Terraform variables customize the deployment (project name, region, which catalog to use, etc.).

### AWS

```bash
cd aws

# Option 1: Copy the example and edit it
cp terraform.tfvars.example terraform.tfvars

# Option 2: Use a pre-built quickstart file
cp ../examples/aws-glue-quickstart.tfvars terraform.tfvars
# or: cp ../examples/aws-nessie-quickstart.tfvars terraform.tfvars
```

Open `terraform.tfvars` in your editor. Here's what each variable means:

```hcl
# Required: a name for your project (used in resource names like "myproject-dev-lakehouse")
project_name = "myproject"

# Environment label (dev, staging, prod) — used in resource names and tags
environment = "dev"

# AWS region where resources will be created
aws_region = "us-east-1"

# Which catalog to use:
#   "glue"   — simplest, serverless, recommended for most teams
#   "nessie" — adds Git-like data branching, requires VPC + Fargate
catalog_type = "glue"

# Only needed if catalog_type = "nessie":
# nessie_image_tag = "0.99.0"
# vpc_cidr = "10.0.0.0/16"
```

### GCP

```bash
cd gcp
cp terraform.tfvars.example terraform.tfvars
# or: cp ../examples/gcp-quickstart.tfvars terraform.tfvars
```

```hcl
# Required
project_name   = "myproject"
gcp_project_id = "my-gcp-project-123"    # ← your GCP project ID (not name)

# Optional (defaults shown)
environment  = "dev"
gcp_region   = "us-central1"
gcp_location = "US"           # BigQuery dataset location (US or EU)
```

---

## Step 3: Deploy Infrastructure

These three commands do all the work:

```bash
# 1. Download provider plugins (AWS/GCP Terraform modules)
#    Run this once, or after changing provider versions
terraform init

# 2. Preview what will be created (dry run — nothing changes yet)
#    Read through the output to verify it looks right
terraform plan

# 3. Create the infrastructure (will ask you to type "yes" to confirm)
terraform apply
```

**What gets created (AWS Glue path)**:
- S3 bucket with encryption, versioning, and lifecycle policies
- Glue database with Iceberg table shells registered
- Athena workgroup with pre-built CREATE TABLE and time-travel queries
- Three IAM roles (reader, writer, admin) with column-level permissions
- Lake Formation resource registration

**What gets created (AWS Nessie path)**:
- Everything above, except Glue/Athena/Lake Formation
- VPC with public and private subnets, NAT gateway
- ECS Fargate cluster running a Nessie container
- Application Load Balancer (ALB) in front of Nessie
- DynamoDB table for Nessie's version store

**What gets created (GCP path)**:
- GCS bucket with uniform access and lifecycle policies
- BigQuery dataset
- BigLake connection with a service account
- External Iceberg tables registered via DDL
- Three service accounts (reader, writer, admin)
- Data Catalog taxonomy with "Restricted" policy tag

### Viewing Outputs

After `terraform apply` completes, view key outputs:

```bash
# Show all outputs
terraform output

# Example output (AWS Glue path):
# lakehouse_bucket_name = "myproject-dev-lakehouse"
# glue_database_name    = "myproject_dev"
# athena_workgroup      = "myproject-dev-lakehouse"
# catalog_type          = "glue"
```

---

## Step 4: Set Up Dagster Pipelines

Dagster orchestrates data pipelines. The template includes stub assets (skeleton code) for each table type — you'll replace these with your actual data logic.

### Install

```bash
cd dagster

# Create a virtual environment (recommended)
python3 -m venv .venv
source .venv/bin/activate    # On Windows: .venv\Scripts\activate

# Install the project and dev dependencies
pip install -e ".[dev]"
```

### Configure the Backend

Tell Dagster which catalog to connect to:

```bash
# AWS with Glue (default)
export LAKEHOUSE_BACKEND=aws-glue

# AWS with Nessie (also set the Nessie endpoint from terraform output)
export LAKEHOUSE_BACKEND=aws-nessie
export NESSIE_URI=http://myproject-dev-nessie-1234567890.us-east-1.elb.amazonaws.com/api/v2

# GCP
export LAKEHOUSE_BACKEND=gcp
export ICEBERG_REST_URI=<your-iceberg-rest-endpoint>
export GCP_PROJECT_ID=my-gcp-project-123
```

### Run Locally

```bash
dagster dev
```

Open http://localhost:3000 in your browser. You should see:

- **Asset graph**: Three assets (event_stream, scd_type2, feature_table) shown as nodes
- **Launchpad**: Click an asset and "Materialize" to run it
- **Sensors**: The schema_drift_sensor listed (starts paused — toggle it on when ready)

### Run with Docker (Alternative)

```bash
cd dagster

# Set the backend as an environment variable
export LAKEHOUSE_BACKEND=aws-glue

# Start both the webserver and daemon
docker-compose up --build

# Open http://localhost:3000
```

---

## Step 5: Configure Data Quality with Soda (Optional)

[Soda](https://www.soda.io/) runs automated checks on your data (e.g., "are there any null IDs?" or "is the data from the last 24 hours?").

### Create a Soda Configuration File

Soda needs a `configuration.yaml` that tells it how to connect to your data source. Create this file at `dagster/lakehouse/quality/configuration.yaml`:

**For AWS (using DuckDB to read Parquet files from S3)**:

```yaml
data_source lakehouse:
  type: duckdb
  path: ":memory:"
  configuration:
    - INSTALL httpfs
    - LOAD httpfs
    - SET s3_region='us-east-1'
```

**For AWS (using Spark with Glue catalog)**:

```yaml
data_source lakehouse:
  type: spark_df
  configuration:
    spark.sql.catalog.glue_catalog: org.apache.iceberg.spark.SparkCatalog
    spark.sql.catalog.glue_catalog.catalog-impl: org.apache.iceberg.aws.glue.GlueCatalog
    spark.sql.catalog.glue_catalog.warehouse: s3://myproject-dev-lakehouse/
```

### Run a Soda Check Manually

```bash
# From the dagster/ directory
soda scan -d lakehouse -c lakehouse/quality/configuration.yaml \
  lakehouse/quality/soda_checks/event_stream_checks.yaml
```

This will output something like:

```
Scan summary:
5/5 checks PASSED:
    event_stream in lakehouse
      Event stream has data [PASSED]
      event_id is never null [PASSED]
      ...
```

---

## Step 6: Configure Alerting (Optional)

The schema drift sensor and quality checks can send alerts when something goes wrong. Configure one or both:

### AWS SNS (Email / SMS / Lambda)

```bash
# Create an SNS topic
aws sns create-topic --name lakehouse-alerts
# Note the TopicArn in the output

# Subscribe your email
aws sns subscribe \
  --topic-arn arn:aws:sns:us-east-1:123456789012:lakehouse-alerts \
  --protocol email \
  --notification-endpoint your-email@company.com
# Check your email and confirm the subscription

# Tell Dagster to use this topic
export ALERT_SNS_TOPIC_ARN=arn:aws:sns:us-east-1:123456789012:lakehouse-alerts
```

### Slack Webhook

```bash
# 1. In Slack: go to your workspace settings → Apps → Incoming Webhooks
# 2. Create a webhook for your alerts channel
# 3. Copy the webhook URL

export ALERT_SLACK_WEBHOOK_URL=<your-slack-webhook-url>
```

---

## Verification Checklist

Run through these to confirm everything is working:

```bash
# 1. Terraform validates (no syntax errors)
make validate

# 2. Terraform plan succeeds (dry run)
make plan-aws-glue       # or: make plan-aws-nessie, make plan-gcp

# 3. Dagster starts and shows the asset graph
cd dagster && dagster dev
# → Open http://localhost:3000
# → You should see 3 assets in the graph

# 4. YAML templates are well-formed
# (requires yamllint: pip install yamllint)
yamllint table-templates/
```

---

## Tear Down

When you're done (or want to start fresh), destroy all created resources:

```bash
cd aws    # or: cd gcp
terraform destroy
# Terraform will list everything it will delete. Type "yes" to confirm.
```

**Warning**: This permanently deletes all infrastructure including the S3/GCS bucket and all data in it. Make sure you've backed up anything you need.

---

## Troubleshooting

### "Error: No valid credential sources found"

Terraform can't authenticate to your cloud provider. Make sure:
- **AWS**: Run `aws sts get-caller-identity` — if this fails, run `aws configure`
- **GCP**: Run `gcloud auth application-default login`

### "Error: Backend configuration changed"

You changed the backend block after running `terraform init`. Run:
```bash
terraform init -reconfigure
```

### "Error: Resource already exists"

Something with the same name already exists (e.g., an S3 bucket). Either:
- Change `project_name` or `environment` in your tfvars to get a different name
- Import the existing resource: `terraform import <resource_address> <resource_id>`

### Dagster can't connect to the catalog

Make sure `LAKEHOUSE_BACKEND` is set and matches your deployed infrastructure. For Nessie, verify the `NESSIE_URI` is reachable:
```bash
curl http://your-nessie-endpoint/api/v2/config
# Should return JSON with Nessie configuration
```
