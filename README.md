# Iceberg Lakehouse Quickstart IaC

Production-grade Iceberg lakehouse foundation for AWS and GCP — deploy in under an hour.

## What Is This?

A **lakehouse** combines the low-cost storage of a data lake (files in S3/GCS) with the structure and query performance of a data warehouse. [Apache Iceberg](https://iceberg.apache.org/) is an open table format that makes this possible — it adds features like schema evolution, time-travel queries, and ACID transactions on top of plain Parquet files.

This repo is an **Infrastructure as Code (IaC) template** that sets up everything you need:

| Layer | What it does | Tools used |
|-------|-------------|------------|
| **Storage** | Creates a cloud bucket for your data files | S3 (AWS) or GCS (GCP) |
| **Catalog** | Tracks which tables exist and where their data lives | AWS Glue, Nessie, or GCP BigLake |
| **Query Engine** | Lets you run SQL against your Iceberg tables | Amazon Athena (AWS) |
| **Governance** | Controls who can see which columns (e.g. hide PII from analysts) | Lake Formation (AWS) or Data Catalog policy tags (GCP) |
| **Pipelines** | Scheduled jobs that load, transform, and validate data | Dagster (Python) |
| **Data Quality** | Automated checks like "no nulls in this column" or "data is fresh" | Soda |

## How the Pieces Fit Together

```
You define tables once in YAML files (table-templates/)
         │
         ├──→ Terraform reads them to create cloud infrastructure
         │      (buckets, catalog entries, IAM permissions)
         │
         └──→ Dagster reads them to build data pipelines
                (ingestion, transformation, quality checks)
```

This "single source of truth" pattern means your infrastructure and pipelines never drift apart. Add a column in the YAML, and both sides pick it up.

## Choose Your Path

This template supports three configurations. Pick the one that fits your stack:

### Option 1: AWS + Glue Catalog (Recommended for most teams)

**Best for**: Teams already on AWS who want the simplest setup with zero servers to manage.

[AWS Glue](https://aws.amazon.com/glue/) is a serverless metadata catalog — it tracks your tables' schemas and where their data files live in S3. [Amazon Athena](https://aws.amazon.com/athena/) lets you query those tables with standard SQL, paying only per query.

```bash
cd aws
cp terraform.tfvars.example terraform.tfvars
# Open terraform.tfvars and fill in your project name, region, etc.

terraform init    # Download required providers
terraform plan    # Preview what will be created (nothing changes yet)
terraform apply   # Create the infrastructure (type "yes" to confirm)
```

### Option 2: AWS + Nessie Catalog

**Best for**: Teams that want Git-like branching for data (create a branch, experiment, merge back).

[Nessie](https://projectnessie.org/) is an open-source catalog that adds version control to your data lake. This path runs Nessie as a container on [AWS ECS Fargate](https://aws.amazon.com/fargate/) (serverless containers) with a load balancer in front. It costs more than Glue but gives you data branching.

```bash
cd aws
cp ../examples/aws-nessie-quickstart.tfvars terraform.tfvars
# Edit terraform.tfvars — you'll need to set vpc_cidr if the default conflicts

terraform init
terraform plan
terraform apply
```

### Option 3: GCP + BigLake

**Best for**: Teams on Google Cloud who want Iceberg tables queryable from BigQuery.

[BigLake](https://cloud.google.com/bigquery/docs/biglake-intro) connects BigQuery to external data in GCS. Your data stays in open Iceberg format, but you query it through BigQuery's familiar SQL interface.

```bash
cd gcp
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your GCP project ID, region, etc.

terraform init
terraform plan
terraform apply
```

### Running the Data Pipelines (After Infrastructure Is Deployed)

[Dagster](https://dagster.io/) is a Python-based data orchestrator — think of it as a scheduler that runs your data jobs in the right order and shows you a visual graph of dependencies.

```bash
cd dagster
pip install -e ".[dev]"

# Tell Dagster which cloud backend to talk to:
export LAKEHOUSE_BACKEND=aws-glue  # or: aws-nessie, gcp

dagster dev
# Open http://localhost:3000 to see the asset graph
```

## Repository Layout

```
iceberg-quickstart-iac/
│
├── table-templates/         # YAML table definitions (THE source of truth)
│   ├── event_stream.yaml    #   Clickstream / event log table
│   ├── scd_type2.yaml       #   Slowly-changing dimension (customer records, etc.)
│   └── feature_table.yaml   #   ML feature store table
│
├── aws/                     # Terraform code for AWS
│   ├── main.tf              #   Wires all modules together
│   ├── variables.tf         #   What you can configure (region, catalog type, etc.)
│   └── modules/             #   Reusable infrastructure building blocks
│       ├── storage/         #     S3 bucket with encryption + lifecycle
│       ├── catalog_glue/    #     Glue database + table registration
│       ├── catalog_nessie/  #     Nessie on ECS Fargate + DynamoDB
│       ├── athena/          #     Query workgroup + pre-built SQL
│       ├── iam/             #     Permissions (who can read which columns)
│       └── networking/      #     VPC (only created for Nessie path)
│
├── gcp/                     # Terraform code for GCP
│   └── modules/
│       ├── storage/         #     GCS bucket
│       ├── biglake/         #     BigQuery dataset + BigLake connection
│       └── iam/             #     Service accounts + column-level security
│
├── dagster/                 # Data pipeline code (Python)
│   └── lakehouse/
│       ├── assets/          #     One file per table type (the actual data jobs)
│       ├── resources/       #     Iceberg connection config
│       ├── quality/         #     Soda data quality checks
│       └── sensors/         #     Automated monitors (schema drift detection)
│
├── examples/                # Ready-to-use variable files
├── docs/                    # Detailed documentation
└── Makefile                 # Convenience commands (make validate, make plan-aws-glue, etc.)
```

## Documentation

- [Architecture](docs/architecture.md) — How the system works and why it's designed this way
- [Deployment Guide](docs/deployment-guide.md) — Step-by-step setup instructions with prerequisites
- [Table Template Reference](docs/table-template-reference.md) — How to define your own tables

## Prerequisites

| Tool | Version | What it does | Install |
|------|---------|-------------|---------|
| Terraform | >= 1.5 | Creates cloud infrastructure from code | [Install guide](https://developer.hashicorp.com/terraform/install) |
| AWS CLI | v2 | Authenticates Terraform to your AWS account | [Install guide](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html) |
| gcloud CLI | latest | Authenticates Terraform to your GCP project | [Install guide](https://cloud.google.com/sdk/docs/install) |
| Python | >= 3.10 | Runs Dagster pipelines | [python.org](https://www.python.org/downloads/) |
| Docker | latest | Optional: run Dagster locally via docker-compose | [Install guide](https://docs.docker.com/get-docker/) |

## License

Apache 2.0 — see [LICENSE](LICENSE).
