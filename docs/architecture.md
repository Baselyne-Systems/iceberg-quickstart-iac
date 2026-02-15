# Architecture

## The Big Picture

A traditional data warehouse stores data in a proprietary format controlled by one vendor. A **data lakehouse** stores data as open-format files (Parquet) in cheap object storage (S3 or GCS), then layers on warehouse-like features through an **open table format** called [Apache Iceberg](https://iceberg.apache.org/).

Iceberg gives you:
- **Schema evolution** — add, rename, or drop columns without rewriting data
- **Time-travel** — query data as it was at any point in the past
- **ACID transactions** — concurrent reads and writes don't corrupt data
- **Partition evolution** — change how data is partitioned without rewriting files

This template automates the full setup: cloud infrastructure, metadata catalog, permissions, data pipelines, and quality checks.

## System Overview

```
┌──────────────────────────────────────────────────────────────┐
│                    table-templates/*.yaml                      │
│                 (single source of truth)                       │
│  Defines: table names, columns, types, partitions, access     │
└────────────┬─────────────────────────────┬───────────────────┘
             │                             │
      Terraform reads YAML           Dagster reads YAML
      at plan/apply time              at pipeline runtime
             │                             │
             ▼                             ▼
┌─────────────────────────┐   ┌─────────────────────────────┐
│   Cloud Infrastructure   │   │      Data Pipelines          │
│                          │   │                              │
│  Storage (S3 / GCS)      │   │  Assets (Python jobs that    │
│    └─ encrypted bucket   │   │    read/transform/write      │
│       with lifecycle     │   │    data into Iceberg tables) │
│       policies           │   │                              │
│                          │   │  Quality Checks (Soda scans  │
│  Catalog                 │   │    that validate data after   │
│    ├─ AWS Glue (option 1)│   │    each pipeline run)        │
│    ├─ Nessie  (option 2) │   │                              │
│    └─ BigLake (option 3) │   │  Schema Drift Sensor         │
│                          │   │    (alerts if live table      │
│  Permissions             │   │    doesn't match YAML def)   │
│    ├─ Reader role        │   │                              │
│    ├─ Writer role        │   └─────────────────────────────┘
│    └─ Admin role         │
└─────────────────────────┘
```

## Why YAML Table Templates?

A common problem in data platforms: the infrastructure team defines tables one way, the pipeline team defines them another way, and they slowly drift apart. A column gets added in the pipeline but never in the catalog. Permissions don't match the actual schema.

This template solves that with **one YAML file per table** that both Terraform and Dagster read:

```yaml
# table-templates/event_stream.yaml
name: event_stream
namespace: lakehouse
columns:
  - name: user_id
    type: string
    pii: true                    # ← This flag...
    access_level: restricted     # ← ...and this flag...
```

- **Terraform** reads `access_level: restricted` and creates IAM rules that hide `user_id` from the reader role
- **Dagster** reads the column list and builds a matching PyArrow schema for pipeline code
- **Schema drift sensor** compares the live Iceberg table against this YAML and alerts on mismatches

One file. Two consumers. Zero drift.

## Choosing an AWS Catalog: Glue vs. Nessie

On AWS, you pick a **catalog** — the service that tracks which Iceberg tables exist and where their data files live.

### AWS Glue (Default)

```
Your SQL Query  →  Athena  →  Glue Catalog  →  S3 (Parquet files)
                               "event_stream     "s3://bucket/
                                lives at          lakehouse/
                                s3://..."          event_stream/"
```

- **What it is**: A fully managed, serverless metadata service from AWS
- **Cost**: ~$1/month per million objects cataloged (essentially free for most workloads)
- **When to use**: You want the simplest setup. Most teams should start here.
- **Limitation**: No data branching — every write goes to the main "branch"

### Nessie

```
Your SQL Query  →  Query Engine  →  Nessie (on Fargate)  →  S3
                                      │
                                      ├── main branch
                                      ├── dev branch (experiment here)
                                      └── feature-x branch
```

- **What it is**: An open-source Git-like catalog that lets you branch, tag, and merge data
- **Cost**: ~$30-80/month (Fargate container + DynamoDB + ALB)
- **When to use**: You need to experiment with data without affecting production (e.g., testing a new transformation before merging it)
- **Architecture**: Runs as a Docker container on ECS Fargate (serverless), backed by DynamoDB for version storage, with an ALB (load balancer) for API access

This template handles all the Nessie infrastructure for you — VPC, subnets, security groups, IAM roles, container definition, health checks, and load balancer. Every operational knob (CPU/memory sizing, auto-scaling limits, HTTPS, access logging, SNS alarms) is exposed as a root-level Terraform variable — see the [Configuration Reference](configuration-reference.md).

## GCP Path: BigLake

```
BigQuery SQL  →  BigLake Connection  →  GCS (Parquet files)
                  │
                  └── reads Iceberg metadata from GCS
                      to serve structured tables in BigQuery
```

- **What it is**: BigQuery's native ability to query external data stored in open formats
- **Cost**: BigQuery on-demand pricing (per TB scanned) — no additional catalog cost
- **When to use**: Your team already uses BigQuery and wants Iceberg without leaving the BQ ecosystem

The template creates a BigQuery dataset, a BigLake connection (with a service account that can read your GCS bucket), and registers each table via DDL.

## Column-Level Governance: How Permissions Work

Iceberg itself has no access control — it's a file format, not a security system. Governance is enforced by the **catalog/query engine layer** above Iceberg.

### The Problem

Your `event_stream` table has a `user_id` column that's PII (personally identifiable information). You want analysts to query the table but not see `user_id`.

### The Solution

In your YAML template, mark sensitive columns:

```yaml
columns:
  - name: user_id
    type: string
    pii: true
    access_level: restricted  # only writer and admin roles can see this
  - name: event_type
    type: string
    access_level: public      # everyone can see this (default)
```

The IAM modules translate this into platform-specific enforcement:

**AWS (Lake Formation)**:
- The **reader** role gets `SELECT` permission on all columns *except* those marked `restricted`
- The **writer** role gets `SELECT`, `INSERT`, `DELETE` on all columns
- The **admin** role gets full database permissions

**GCP (Data Catalog Policy Tags)**:
- A "Restricted" policy tag is created in Data Catalog
- Only the writer and admin service accounts get the `categoryFineGrainedReader` role
- The reader service account cannot see tagged columns in BigQuery results

### Three Roles, Explained

| Role | Can read public columns | Can read restricted columns | Can write data | Can alter tables |
|------|------------------------|---------------------------|----------------|-----------------|
| **Reader** | Yes | No | No | No |
| **Writer** | Yes | Yes | Yes | No |
| **Admin** | Yes | Yes | Yes | Yes |

## Data Pipelines: How Dagster Works Here

[Dagster](https://dagster.io/) is a data orchestrator — it defines **what** data should be produced (assets) and handles scheduling, retries, and monitoring.

### Assets

Each table template has a corresponding Dagster **asset** (a Python function that produces data):

| Asset | Source file | What it does |
|-------|-----------|-------------|
| `event_stream` | `assets/event_streams.py` | Ingests raw event data (replace stub with your Kafka consumer, API pull, etc.) |
| `scd_type2` | `assets/dimensions.py` | Processes slowly-changing dimension updates (replace stub with your CDC logic) |
| `feature_table` | `assets/features.py` | Computes ML features (replace stub with your feature engineering code) |

The included assets are **stubs** — they define the correct schema but return empty tables. Replace the body of each asset function with your actual data logic.

### IO Manager

The **IO manager** (`resources/iceberg.py`) handles reading from and writing to Iceberg tables. It's a factory that configures the right catalog connection based on an environment variable:

```bash
export LAKEHOUSE_BACKEND=aws-glue    # Connects to Glue catalog
export LAKEHOUSE_BACKEND=aws-nessie  # Connects to Nessie REST API
export LAKEHOUSE_BACKEND=gcp         # Connects to GCP Iceberg REST catalog
```

You don't need to change any asset code when switching backends — the IO manager abstracts the difference away.

### Schema Drift Sensor

The **schema drift sensor** (`sensors/schema_drift.py`) runs every hour and:

1. Loads all YAML table templates
2. Connects to the live Iceberg catalog
3. Compares each table's actual columns to the expected columns
4. Sends an alert (SNS or Slack) if there's a mismatch

Example alert: *"Schema drift detected in lakehouse.event_stream. Extra columns: {debug_flag}. Missing columns: {session_id}."*

## Data Quality: How Soda Works Here

[Soda](https://www.soda.io/) is a data quality tool that runs checks like "no null values in this column" or "row count is greater than zero." This template includes pre-built check files for each table.

### How It Works

1. Soda runs as a **subprocess** (command-line tool), not a native Dagster integration
2. The Dagster op in `quality/runner.py` calls `soda scan` with a check file
3. Check files are YAML definitions in `quality/soda_checks/`

### Example Check (event_stream_checks.yaml)

```yaml
checks for event_stream:
  - row_count > 0:                     # Table isn't empty
      name: Event stream has data
  - missing_count(event_id) = 0:       # No null event IDs
      name: event_id is never null
  - duplicate_count(event_id) = 0:     # No duplicate event IDs
      name: event_id is unique
  - freshness(event_timestamp) < 1d:   # Data was updated in the last day
      name: Data is fresh (< 1 day)
```

### Setup Requirement

Soda needs a `configuration.yaml` that tells it how to connect to your data. This file must be generated from Terraform outputs after deployment — it's not included in the template because it contains environment-specific connection details. See the [Deployment Guide](deployment-guide.md) for details.

## Key Design Decisions

### Why not hardcode the Terraform backend?

Each engagement (client project) uses different state storage. The template includes a commented-out backend block in `versions.tf` — uncomment and configure it for your team's S3 bucket, GCS bucket, or Terraform Cloud workspace.

### Why are Iceberg partition specs not set in Glue?

Iceberg manages its own partitions in metadata files — the Glue `partition_keys` field is for Hive-style partitions, which are different. The Glue module registers a "table shell" (schema + location). Actual Iceberg partition specs are applied the first time you write data via Athena DDL or PyIceberg.

### Why pin the Nessie image tag?

Using `latest` for Docker images means your infrastructure can break when Nessie releases a new version. The template pins to a specific version (default: `0.99.0`) so upgrades are intentional. Change it via the `nessie_image_tag` variable.

### Why is dagster-iceberg pinned carefully?

The `dagster-iceberg` package is in preview. The template documents this risk and pins the version in `pyproject.toml`. If stability is critical, the IO manager can be modified to use `pyiceberg` directly instead.
