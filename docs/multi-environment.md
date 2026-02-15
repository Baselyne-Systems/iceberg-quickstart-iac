# Multi-Environment Operations Guide

How to run dev, staging, and prod environments side-by-side using the same codebase.

**Key principle:** Same Terraform modules, same Dagster code — the environment is determined by which variable file you use and which catalog the IO manager connects to.

---

## Terraform: State Isolation

Each environment needs its own Terraform state file. The recommended approach is one state file per environment, using `-backend-config` to switch the key at `terraform init` time.

### Setup

1. Create a shared state bucket (once):

```bash
# AWS
aws s3api create-bucket --bucket my-company-tf-state --region us-east-1
aws dynamodb create-table \
  --table-name tf-locks \
  --attribute-definitions AttributeName=LockID,AttributeType=S \
  --key-schema AttributeName=LockID,KeyType=HASH \
  --billing-mode PAY_PER_REQUEST
```

2. Uncomment the backend block in `aws/versions.tf` (leave the `key` field out — you'll provide it via CLI):

```hcl
terraform {
  backend "s3" {
    bucket         = "my-company-tf-state"
    region         = "us-east-1"
    dynamodb_table = "tf-locks"
    encrypt        = true
    # key is provided via -backend-config at init time
  }
}
```

3. Initialize and deploy each environment:

```bash
cd aws

# ── Dev ───────────────────────────────────────────────────────
terraform init -backend-config="key=iceberg-lakehouse/dev/terraform.tfstate"
terraform plan  -var-file=../environments/dev.tfvars
terraform apply -var-file=../environments/dev.tfvars

# ── Prod ──────────────────────────────────────────────────────
# -reconfigure tells Terraform to switch state files without migrating
terraform init -reconfigure -backend-config="key=iceberg-lakehouse/prod/terraform.tfstate"
terraform plan  -var-file=../environments/prod.tfvars
terraform apply -var-file=../environments/prod.tfvars
```

### Why This Is Safe

Resource names include `${environment}` (e.g., `lakehouse-dev-lakehouse` vs `lakehouse-prod-lakehouse`), so dev and prod never collide. The `prevent_destroy` lifecycle rules on storage resources work correctly since each environment's bucket has a unique name.

### GCP Equivalent

```bash
cd gcp

# Dev
terraform init -backend-config="prefix=iceberg-lakehouse/dev"
terraform plan  -var-file=../environments/dev.tfvars

# Prod
terraform init -reconfigure -backend-config="prefix=iceberg-lakehouse/prod"
terraform plan  -var-file=../environments/prod.tfvars
```

### Tip: Separate Workspaces

If you prefer not to `init -reconfigure` constantly, keep separate working directories:

```bash
mkdir -p deploy/dev deploy/prod

# Each directory gets its own .terraform/ and state
cd deploy/dev  && terraform init -backend-config="key=iceberg-lakehouse/dev/terraform.tfstate" -chdir=../../aws
cd deploy/prod && terraform init -backend-config="key=iceberg-lakehouse/prod/terraform.tfstate" -chdir=../../aws
```

---

## Dagster: Per-Environment Instances

Each environment connects to a different catalog/bucket. The same asset code runs everywhere — the environment is determined by the `.env` file.

### Environment Files

Pre-built environment files are provided:

| File | Purpose |
|------|---------|
| `.env.dev` | Dev catalog, admin access, alerting off |
| `.env.prod` | Prod catalog, reader access, alerting on |
| `.env.example` | Full reference with all variables documented |

Edit each file to set the correct endpoints from your Terraform outputs:

```bash
cd dagster
# After deploying dev infrastructure:
terraform -chdir=../aws output    # copy nessie_endpoint, bucket name, etc.
# Edit .env.dev with dev-specific values
```

### Running Locally (Side-by-Side)

Run two Dagster instances on different ports:

```bash
# Terminal 1 — dev on default port 3000
source .env.dev && dagster dev

# Terminal 2 — prod on port 3001
source .env.prod && dagster dev -p 3001
```

### Running with Docker Compose (Side-by-Side)

Use `--project-name` to isolate container names and networks:

```bash
# Dev
docker compose --env-file .env.dev --project-name lakehouse-dev up -d

# Prod (with production overlay — stricter resources, no source mounts)
docker compose \
  -f docker-compose.yaml -f docker-compose.prod.yaml \
  --env-file .env.prod --project-name lakehouse-prod up -d
```

The `--project-name` flag ensures containers, volumes, and networks get unique names (`lakehouse-dev-dagster-webserver` vs `lakehouse-prod-dagster-webserver`), so they don't conflict.

### Production Compose Overlay

`docker-compose.prod.yaml` layers production settings on top of the base compose file:

- Removes source-code volume mounts (uses the baked Docker image)
- Removes exposed ports (put behind a reverse proxy like nginx or Traefik)
- Increases resource limits (4 CPU / 4 GB for webserver)
- Sets `restart: always` instead of `unless-stopped`

---

## Soda Quality Checks

Generate a Soda `configuration.yaml` per environment, each pointing to the correct data source.

### Per-Environment Config

```bash
# dagster/lakehouse/quality/configuration.dev.yaml
data_source lakehouse:
  type: duckdb
  path: ":memory:"
  configuration:
    - INSTALL httpfs
    - LOAD httpfs
    - SET s3_region='us-east-1'
    # Reads from dev bucket: lakehouse-dev-lakehouse
```

```bash
# dagster/lakehouse/quality/configuration.prod.yaml
data_source lakehouse:
  type: duckdb
  path: ":memory:"
  configuration:
    - INSTALL httpfs
    - LOAD httpfs
    - SET s3_region='us-east-1'
    # Reads from prod bucket: lakehouse-prod-lakehouse
```

### Running Checks Per Environment

```bash
# Check dev data
soda scan -d lakehouse -c lakehouse/quality/configuration.dev.yaml \
  lakehouse/quality/soda_checks/event_stream_checks.yaml

# Check prod data
soda scan -d lakehouse -c lakehouse/quality/configuration.prod.yaml \
  lakehouse/quality/soda_checks/event_stream_checks.yaml
```

---

## Cost & Resource Comparison

Typical settings across environments — see `environments/dev.tfvars` and `environments/prod.tfvars` for the full variable files.

| Setting | Dev | Prod |
|---------|-----|------|
| **Nessie CPU / Memory** | 256 / 512 MiB | 1024 / 2048 MiB |
| **Nessie min tasks** | 1 | 2 (HA across AZs) |
| **HTTPS** | No (HTTP only) | Yes (ACM certificate) |
| **CloudTrail** | Off | On |
| **Log retention** | 30 days | 365 days (SOC2) / 2190 days (HIPAA) |
| **Access logging** | Off | S3 + ALB access logs |
| **Dagster access level** | `admin` | `reader` (PII masked) |
| **Alerting** | Off | SNS + Slack |
| **Docker resources** | Default (2 CPU / 2 GB) | 4 CPU / 4 GB webserver |
| **Estimated Nessie cost** | ~$10/month | ~$60-200/month |

---

## Makefile Shortcuts

```bash
# Validate with environment-specific tfvars (no backend required)
make plan-aws-dev
make plan-aws-prod
```

---

## Checklist: Adding a New Environment

1. **Create a tfvars file**: Copy `environments/dev.tfvars` to `environments/staging.tfvars` and adjust settings
2. **Initialize Terraform state**: `terraform init -backend-config="key=iceberg-lakehouse/staging/terraform.tfstate"`
3. **Deploy infrastructure**: `terraform apply -var-file=../environments/staging.tfvars`
4. **Create a Dagster .env file**: Copy `.env.dev` to `.env.staging`, update endpoints from `terraform output`
5. **Run Dagster**: `docker compose --env-file .env.staging --project-name lakehouse-staging up -d`
6. **Create Soda config**: Copy `configuration.dev.yaml` to `configuration.staging.yaml`, update bucket references
