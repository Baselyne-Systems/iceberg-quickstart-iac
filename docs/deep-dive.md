# The Complete Guide to This Lakehouse

Everything you need to understand, explain, and extend this system — from first principles to production hardening.

---

## Table of Contents

1. [The Big Idea](#the-big-idea)
2. [Apache Iceberg: Why It Matters](#apache-iceberg-why-it-matters)
3. [The YAML Single Source of Truth](#the-yaml-single-source-of-truth)
4. [Cloud Storage Layer](#cloud-storage-layer)
5. [Catalog Layer: Glue vs Nessie vs BigLake](#catalog-layer-glue-vs-nessie-vs-biglake)
6. [IAM and Column-Level Governance](#iam-and-column-level-governance)
7. [Dagster Pipelines](#dagster-pipelines)
8. [Schema Drift Detection](#schema-drift-detection)
9. [Data Quality with Soda](#data-quality-with-soda)
10. [Terraform Patterns](#terraform-patterns)
11. [Docker and Container Security](#docker-and-container-security)
12. [CI/CD Pipeline](#cicd-pipeline)
13. [Dependency Management](#dependency-management)
14. [Compliance Architecture](#compliance-architecture)
15. [Secrets Management](#secrets-management)
16. [Networking](#networking)
17. [Cost Model](#cost-model)
18. [Key Design Tradeoffs](#key-design-tradeoffs)
19. [Failure Modes and How to Handle Them](#failure-modes-and-how-to-handle-them)
20. [Extending the System](#extending-the-system)

---

## The Big Idea

A **lakehouse** combines two things:

1. **Data lake**: Files (Parquet) in cheap object storage (S3/GCS). Scales to petabytes. Costs pennies per GB/month.
2. **Data warehouse**: Schema enforcement, ACID transactions, SQL queries. The structure that makes data usable.

Traditional data lakes are a mess — files dumped into buckets with no schema, no transactions, no way to know what's current. Traditional data warehouses are expensive and locked to one vendor.

Apache Iceberg bridges the gap. Your data stays as Parquet files in S3/GCS (cheap, open, portable), but Iceberg adds a metadata layer that gives you warehouse features: schemas, transactions, time-travel, partition evolution.

**This repo automates the entire setup.** One `terraform apply` creates the storage, catalog, permissions, and audit trail. One `dagster dev` runs the pipelines.

---

## Apache Iceberg: Why It Matters

Iceberg is a **table format** — it defines how to organize data files and metadata so that multiple engines (Athena, Spark, Trino, DuckDB) can all read the same tables.

### How Iceberg Works

```
Iceberg Table
├── metadata/
│   ├── v1.metadata.json      ← Schema, partitions, snapshots
│   ├── v2.metadata.json      ← After a write (new snapshot)
│   ├── snap-1234.avro        ← Manifest list (which files belong to this snapshot)
│   └── manifest-5678.avro    ← Manifest (actual file paths + stats)
└── data/
    ├── 00001-file1.parquet   ← Actual data
    ├── 00002-file2.parquet
    └── 00003-file3.parquet
```

Each **write** creates a new metadata file (atomic pointer swap), not a new copy of all data. This gives you:

- **ACID transactions**: Two writers can't corrupt each other; one wins, the other retries.
- **Time-travel**: Every write creates a snapshot. Query any past state: `SELECT * FROM t FOR SYSTEM_VERSION AS OF 1234`.
- **Schema evolution**: Add/rename/drop columns without rewriting data files.
- **Partition evolution**: Change how data is partitioned (e.g., daily → hourly) without rewriting existing files.
- **Hidden partitioning**: Queries don't need `WHERE dt = '2024-01-15'` — Iceberg uses metadata to prune partitions automatically.

### Why Not Delta Lake or Hudi?

All three are valid. Iceberg won here because:

- **Engine-agnostic**: Works with Athena, Spark, Trino, Flink, DuckDB, BigQuery. Delta is tightly coupled to Spark/Databricks.
- **Open governance**: Apache Foundation project, not controlled by one vendor.
- **Partition evolution**: Iceberg handles this natively; Delta requires rewriting.
- **BigQuery support**: Google added native Iceberg support via BigLake.

**Tradeoff**: Delta has a larger ecosystem (Databricks invests heavily). Hudi has better upsert performance for CDC workloads. Iceberg is the best general-purpose choice.

---

## The YAML Single Source of Truth

This is the most important design decision in the entire repo.

### The Problem

In most data platforms, table definitions live in two places:

1. **Infrastructure** (Terraform/CloudFormation) — creates the Glue table, sets columns and types.
2. **Pipelines** (Python/Spark) — reads and writes data with its own schema definition.

These inevitably drift apart. Someone adds a column in Glue but forgets the pipeline. Someone changes a type in Python but forgets Terraform. Now your pipeline writes `int` but your catalog says `string`, and queries silently return garbage.

### The Solution

One YAML file per table in `table-templates/`. Both Terraform and Dagster read from it:

```yaml
# table-templates/event_stream.yaml
name: event_stream
namespace: lakehouse
description: Clickstream and application events
columns:
  - name: event_id
    type: string
    required: true
  - name: user_id
    type: string
    access_level: restricted    # ← PII flag: drives IAM + Dagster masking
  - name: event_timestamp
    type: timestamptz
    required: true
  - name: payload
    type: string
partition_spec:
  - column: event_timestamp
    transform: day
properties:
  write.format.default: parquet
  history.expire.max-snapshot-age-ms: "604800000"  # 7 days
tags:
  domain: analytics
  pattern: append-only
```

**Terraform reads this** (in `locals.tf`):

```hcl
locals {
  table_templates = {
    for f in fileset("${path.module}/../table-templates", "*.yaml") :
    trimsuffix(f, ".yaml") => yamldecode(file("${path.module}/../table-templates/${f}"))
  }
}
```

It passes these to the catalog module, which creates one Glue/BigQuery table per template.

**Dagster reads this** (in `utils/table_loader.py`):

```python
@functools.lru_cache(maxsize=1)
def load_table_templates() -> dict[str, dict]:
    templates_dir = Path(__file__).parent.parent.parent.parent / "table-templates"
    return {p.stem: yaml.safe_load(p.read_text()) for p in templates_dir.glob("*.yaml")}
```

It builds PyArrow schemas from the same YAML, ensuring the pipeline writes exactly the schema that infrastructure expects.

**The schema drift sensor** closes the loop: every hour, it compares the live Iceberg table schema against the YAML template and alerts if they diverge.

### Adding a New Table

1. Create `table-templates/my_new_table.yaml`
2. Run `terraform apply` — creates the table in Glue/BigQuery
3. Add a Dagster asset in `dagster/lakehouse/assets/` that returns a PyArrow table
4. Or add a `source:` block to the YAML and Dagster auto-generates the asset

No coordination required between infra and pipeline teams.

---

## Cloud Storage Layer

### AWS: S3 (`aws/modules/storage/`)

The S3 bucket is the data lake. All Iceberg data files live here.

**What gets created:**

| Resource | Purpose |
|----------|---------|
| `aws_s3_bucket.lakehouse` | Main data bucket |
| `aws_s3_bucket_versioning` | Enables object versioning (needed for Iceberg time-travel) |
| `aws_s3_bucket_server_side_encryption_configuration` | SSE-KMS with bucket key |
| `aws_s3_bucket_public_access_block` | Blocks all public access (4 rules) |
| `aws_s3_bucket_policy` | Denies non-HTTPS requests (`aws:SecureTransport = false`) |
| `aws_s3_bucket_lifecycle_configuration` | 90d → Standard-IA; old versions expire after 30d |

**Why bucket keys instead of per-object KMS?**

Per-object KMS means every S3 API call (GetObject, PutObject) makes a KMS API call. With thousands of Parquet files, this:
- Adds latency (KMS round-trip per file)
- Can hit KMS request limits (5,500/sec per key)
- Costs more ($0.03 per 10,000 requests)

Bucket keys generate a short-lived data key from your KMS key and reuse it for all objects. Same encryption guarantee, dramatically fewer KMS calls.

**Why Standard-IA at 90 days?**

Standard-IA (Infrequent Access) costs ~60% less per GB but charges per retrieval. Iceberg's metadata tracks which files are "current" and which are old snapshots. After 90 days, most files are only accessed for time-travel queries (infrequent), making IA a good fit.

### Audit Trail (`aws/modules/storage/cloudtrail.tf`)

A separate S3 bucket + CloudTrail trail captures every read and write to the lakehouse bucket.

**Why a separate bucket?**

1. CloudTrail requires specific bucket policies and ACLs. Mixing with the data bucket creates policy conflicts.
2. Audit logs need different retention (7 years for HIPAA) than data files.
3. Separation makes compliance audits simpler — "here's the audit bucket, here's its lifecycle."

**Lifecycle:**
```
Day 0-90:     S3 Standard
Day 90-365:   S3 Standard-IA
Day 365-2555: S3 Glacier
Day 2555:     Delete (7 years total)
```

This exceeds HIPAA's 6-year retention requirement.

### GCP: GCS (`gcp/modules/storage/`)

Equivalent to S3 but with GCP-specific features:

- **Uniform bucket-level access**: No per-object ACLs (simpler, more secure)
- **CMEK** (optional): KMS key ring + crypto key with 90-day rotation
- **Lifecycle**: 90d → Nearline, old versions expire after 30d
- **Audit logging**: Cloud Audit Log sink → dedicated audit bucket (7-year lifecycle)

**Why CMEK is optional**: Google-managed encryption is on by default. CMEK adds control (you own the key) but also adds operational burden (key rotation, access policies, risk of key deletion = data loss). Most teams don't need CMEK unless compliance requires it.

---

## Catalog Layer: Glue vs Nessie vs BigLake

The catalog answers the question: "What tables exist, what are their schemas, and where are their data files?"

### AWS Glue (`aws/modules/catalog_glue/`)

**What it is**: Serverless metadata service. Registers databases and tables. Athena/Spark/EMR query against it.

**What we create**:
- One Glue database (named `{project}_{environment}`)
- One Glue table per YAML template
- Each table registered as `EXTERNAL_TABLE` with `table_type = "ICEBERG"`

**Why Iceberg partitions are NOT in Glue's `partition_keys`**:

This is a subtle but critical point. Glue has two partition concepts:

1. `partition_keys` — Hive-style partitions. Glue manages separate metadata entries per partition value. The filesystem has `year=2024/month=01/` directories.
2. Iceberg partitions — Managed entirely in Iceberg's metadata files. The filesystem is flat (just numbered Parquet files). Iceberg uses partition stats in manifests for pruning.

If you put Iceberg partitions in `partition_keys`, Glue and Iceberg disagree about partition management, causing query failures. The partition spec is applied when you first write data (via Athena DDL or PyIceberg).

**Cost**: Free (pay only for Athena queries).

**When to use**: Most teams. Zero operational overhead, fully managed.

### Nessie (`aws/modules/catalog_nessie/`)

**What it is**: Open-source Git-like catalog. Runs as a Java (Quarkus) container. Stores version history in DynamoDB.

**Why Git-like branching for data?**

Imagine you want to test a schema migration:

```
main branch:  event_stream (10 columns)
    │
    └── feature/add-device-id branch:
            event_stream (11 columns, + device_id)
            ↑ Data on this branch is isolated
            ↑ Readers on main see the old schema
            ↑ Merge when ready
```

This is powerful for:
- Testing migrations without affecting production
- Running A/B experiments on different table structures
- Rolling back bad changes (reset branch pointer)

**Architecture**:

```
Internet/VPC
    ↓
ALB (port 80/443) ─── TLS terminates here when cert provided
    ↓
ECS Fargate Tasks (private subnets, 512 CPU / 1024 MB default)
    ├── DynamoDB (version store, point-in-time recovery)
    ├── S3 (data files, via PyIceberg)
    └── CloudWatch Logs
```

**Key design decisions**:

1. **DynamoDB over JDBC**: No database server to manage. PAY_PER_REQUEST billing = zero cost at idle.
2. **Private subnets**: Nessie has no authentication by default. Network isolation is the security boundary.
3. **Single NAT gateway**: Cost optimization. Two NATs would add ~$64/month for HA.
4. **Pinned image tag** (`0.99.0`): Prevents surprise breaking changes from `latest`.

**Cost**: ~$30-80/month (Fargate compute + NAT gateway + DynamoDB on-demand).

**When to use**: Teams that need data branching, or want an open-source catalog they control.

### GCP BigLake (`gcp/modules/biglake/`)

**What it is**: BigQuery's way of reading external Iceberg tables in GCS.

**How it works**:
1. BigLake connection: A service account that BigQuery uses to read from GCS.
2. External tables: Created via BigQuery DDL pointing to Iceberg metadata in GCS.
3. Queries: Run through BigQuery's SQL engine, reading Parquet files from GCS.

**Why `google_bigquery_job` instead of `google_bigquery_table`?**

The native Terraform resource `google_bigquery_table` doesn't support Iceberg's external table format (it predates BigLake Iceberg support). The workaround: execute `CREATE EXTERNAL TABLE` DDL as a BigQuery job. The job ID includes an MD5 hash of the DDL — if the schema changes, Terraform recreates the job.

**Cost**: Free to create. Pay per BigQuery query ($5/TB scanned).

**When to use**: Teams on GCP who want Iceberg tables queryable from BigQuery.

---

## IAM and Column-Level Governance

### The Three-Tier Model

Every deployment creates three roles/service accounts:

| Role | Can Read | Can Write | Can Alter Schema | Sees PII Columns |
|------|----------|-----------|-----------------|-----------------|
| **Reader** | Public columns only | No | No | No |
| **Writer** | All columns | Yes | No | Yes |
| **Admin** | All columns | Yes | Yes | Yes |

### How PII Columns Are Marked

In the YAML template:

```yaml
columns:
  - name: user_id
    type: string
    access_level: restricted   # ← This flag
  - name: ip_address
    type: string
    access_level: restricted   # ← This flag
  - name: event_type
    type: string               # No flag = public
```

### Three Levels of Enforcement

**Level 1: Cloud IAM (prevents unauthorized queries)**

AWS (Lake Formation):
```hcl
# Reader gets SELECT but excluded from restricted columns
table_with_columns {
  database_name = "lakehouse_dev"
  name          = "event_stream"
  excluded_column_names = ["user_id", "ip_address"]
}
```

If a reader runs `SELECT user_id FROM event_stream` in Athena, they get `AccessDeniedException`.

GCP (Data Catalog policy tags):
```hcl
# "Restricted" policy tag applied to PII columns
# Writer and admin get roles/datacatalog.categoryFineGrainedReader
# Reader does not → BigQuery redacts those columns
```

**Level 2: Application layer (Dagster IO manager)**

```python
# In resources/iceberg.py
if self._access_level == "reader":
    restricted = get_restricted_columns(template)
    result = result.drop([c for c in restricted if c in result.column_names])
    log_audit_event("pii_columns_dropped", table=name, details={"columns_dropped": restricted})
```

Even if the cloud IAM is misconfigured, Dagster independently masks PII for reader-level workloads.

**Level 3: Audit trail (detects unauthorized access)**

Every read/write is logged:
- CloudTrail records which IAM principal accessed which S3 objects
- Dagster's structured audit logger records which access level was used and whether PII columns were dropped

**Why three levels?** Defense in depth. If one layer fails (misconfigured IAM, bypassed application logic), the others still protect data. An auditor can also verify that all three layers agree.

---

## Dagster Pipelines

### What Dagster Does

Dagster is a data orchestrator. It:

1. **Defines assets**: Python functions that produce data (DataFrames, files, tables).
2. **Tracks dependencies**: Asset A depends on Asset B → runs B first.
3. **Manages IO**: The IO manager handles reading from and writing to Iceberg.
4. **Monitors**: Sensors check for conditions (schema drift) and trigger actions.

### The IO Manager (`resources/iceberg.py`)

This is the most important piece of Dagster code. It abstracts away which catalog backend you're using.

**Write path** (`handle_output`):
```
Asset returns PyArrow Table
    → IO manager gets catalog config from LAKEHOUSE_BACKEND env var
    → Loads Iceberg table from catalog (Glue/Nessie/BigLake)
    → Calls table.overwrite(arrow_table)  # Atomic write
    → Logs audit event
```

**Read path** (`load_input`):
```
Downstream asset needs data
    → IO manager loads Iceberg table
    → Scans to PyArrow Table
    → If access_level == "reader": drops restricted columns
    → Logs audit event
    → Returns PyArrow Table to asset
```

**Backend abstraction**:

```python
def _get_catalog_config():
    backend = os.environ.get("LAKEHOUSE_BACKEND", "aws-glue")
    if backend == "aws-glue":
        return {"type": "glue", "s3.region": region}
    elif backend == "aws-nessie":
        return {"type": "rest", "uri": os.environ["NESSIE_URI"]}
    elif backend == "gcp":
        return {"type": "rest", "uri": os.environ.get("ICEBERG_REST_URI")}
```

Switch backends by changing one environment variable. Zero code changes.

### Assets

Three stub assets are provided:

- `event_streams.py` — Append-only event log pattern
- `dimensions.py` — Slowly-changing dimension (SCD Type 2)
- `features.py` — ML feature store pattern

Each returns an empty PyArrow table with the correct schema (from YAML). You replace the body with your actual data logic.

**Auto-generated source assets** (`source_assets.py`): If a YAML template has a `source:` block, Dagster creates an asset that reads files from S3/GCS and writes to Iceberg. No Python needed — just YAML.

```yaml
source:
  path: s3://my-raw-data/events/
  format: parquet   # or csv, json
```

**Security in source assets**: The code validates that paths start with `s3://` or `gs://` and rejects local filesystem paths. This prevents path traversal attacks where a malicious YAML could read `/etc/passwd`.

### How Assets Connect to YAML

```
YAML Template
    ↓
table_loader.py reads YAML, builds PyArrow schema
    ↓
Asset function uses schema to validate/create data
    ↓
IO manager writes to Iceberg using same schema
    ↓
Schema drift sensor compares live table against YAML
```

---

## Schema Drift Detection

### The Problem

Someone runs `ALTER TABLE event_stream ADD COLUMN debug_flag STRING` in Athena. Now the live table has a column that doesn't exist in the YAML. Downstream pipelines might break, or worse, silently produce wrong results.

### The Solution (`sensors/schema_drift.py`)

Every hour, the sensor:

1. Loads all YAML templates
2. Connects to the Iceberg catalog
3. For each table, compares:
   - **Missing columns**: In YAML but not in live table (someone dropped a column)
   - **Extra columns**: In live table but not in YAML (someone added without updating YAML)
   - **Type mismatches**: Column exists in both but types differ
4. Fires alerts (SNS/Slack) if drift detected
5. Logs structured audit event

### Responding to Drift

**Intentional change**: Update the YAML template to match, run `terraform apply`, done.

**Unintentional change**: Check CloudTrail for `UpdateTable`/`AlterTable` calls. Find who changed it, why, and fix accordingly.

---

## Data Quality with Soda

### What Soda Does

Soda runs SQL-like checks against your data:

```yaml
# quality/soda_checks/event_stream_checks.yaml
checks for event_stream:
  - row_count > 0                        # Table not empty
  - missing_count(event_id) = 0          # No null PKs
  - duplicate_count(event_id) = 0        # PK uniqueness
  - freshness(event_timestamp) < 1d      # Data is recent
```

### Architecture

Soda uses DuckDB as an in-memory engine to run checks against Parquet files. The `soda-core-duckdb` package is the connector.

**Why DuckDB?** It can read Parquet files directly from S3/GCS without a running database. Zero infrastructure needed. The checks run inside the Dagster process.

**Tradeoff**: DuckDB doesn't have Python 3.14 wheels yet, which is why `uv sync` fails on your local machine (Python 3.14). The CI uses Python 3.13. This is a temporary limitation.

---

## Terraform Patterns

### Module Composition

```hcl
# aws/main.tf — simplified
module "storage" { ... }                                    # Always created
module "catalog_glue"  { count = var.catalog_type == "glue" ? 1 : 0 }
module "catalog_nessie" { count = var.catalog_type == "nessie" ? 1 : 0 }
module "networking"    { count = var.catalog_type == "nessie" ? 1 : 0 }
module "athena"        { count = var.catalog_type == "glue" ? 1 : 0 }
module "iam"           { ... }                              # Always created
```

Conditional creation via `count`. Glue path creates no networking or ECS resources. Nessie path creates no Glue or Athena resources. Storage and IAM are always created.

### `for_each` on Table Templates

```hcl
resource "aws_glue_catalog_table" "tables" {
  for_each = var.table_templates
  name     = each.value.name
  # ... columns from each.value.columns
}
```

Add a YAML file → `terraform apply` creates the table. Remove it → `terraform apply` destroys it. The YAML directory is the declarative source.

### Why `yamldecode()` in `locals.tf`

Terraform's built-in `yamldecode()` parses YAML at plan time. No external dependencies (no Python, no scripts). It runs on any machine that has Terraform installed.

### Backend Configuration

The backend block is **commented out** in `versions.tf`. This is deliberate:

- The template can't assume you have an S3 bucket for state
- Different teams use S3, GCS, Terraform Cloud, or local state
- Forcing a specific backend would break first-time setup

Users uncomment and configure the backend for their environment. The deployment guide walks through this.

### State Isolation for Multi-Environment

```bash
# Dev
terraform init -backend-config="key=iceberg-lakehouse/dev/terraform.tfstate"
terraform apply -var-file=../environments/dev.tfvars

# Prod (separate state file, same modules)
terraform init -reconfigure -backend-config="key=iceberg-lakehouse/prod/terraform.tfstate"
terraform apply -var-file=../environments/prod.tfvars
```

Same code, different state files, different variable values. Resource names include `${environment}` to prevent collisions.

---

## Docker and Container Security

### Dockerfile Design (`dagster/Dockerfile`)

```dockerfile
FROM python:3.11-slim                    # Minimal base, no dev tools
RUN apt-get update && apt-get upgrade -y # Patch OS-level CVEs at build time
COPY --from=ghcr.io/astral-sh/uv:latest /uv /usr/local/bin/uv  # Deterministic installs
COPY pyproject.toml uv.lock ./           # Lockfile for reproducible builds
RUN uv export --frozen --no-hashes > requirements.txt && \
    uv pip install --system -r requirements.txt
RUN useradd -m dagster                   # Non-root user
USER dagster                             # Drop privileges
```

**Why `python:3.11-slim` (floating tag)?**

We originally pinned `python:3.11.11-slim`, but that image had 18 unpatched Debian CVEs. The floating `3.11-slim` tag + `apt-get upgrade` ensures each build gets the latest OS patches. The tradeoff: slightly less reproducible builds, but significantly better security posture.

**Why `uv` instead of `pip`?**

- `uv` is 10-100x faster than pip for dependency resolution
- `uv.lock` provides a deterministic lockfile (pip has no native lockfile)
- `uv export --frozen` generates a pinned requirements list from the lockfile

### docker-compose.yaml Security

```yaml
security_opt:
  - "no-new-privileges:true"    # Prevents privilege escalation
cap_drop:
  - ALL                          # Drop all Linux capabilities
read_only: true                  # Filesystem is read-only
tmpfs:
  - /tmp                         # Only /tmp is writable
deploy:
  resources:
    limits:
      cpus: "2"
      memory: 2G                 # OOM killed instead of eating all RAM
```

This is a hardened container configuration. Even if an attacker gets code execution inside the container, they can't:
- Escalate to root
- Write to the filesystem (except /tmp)
- Use Linux capabilities (no `NET_RAW`, no `SYS_ADMIN`, etc.)
- Consume unbounded resources

---

## CI/CD Pipeline

### Pipeline Structure (`.github/workflows/ci.yml`)

```
Push to main or PR
    │
    ├── Job: terraform (parallel)
    │   ├── terraform fmt -check      ← Code style
    │   ├── terraform validate        ← Syntax + type errors
    │   └── Checkov scan              ← Policy-as-code (security misconfigs)
    │
    ├── Job: python (parallel)
    │   ├── uv sync --frozen          ← Lockfile integrity
    │   ├── ruff check + format       ← Lint + style
    │   ├── pytest                    ← Unit tests (58 tests)
    │   └── pip-audit                 ← Known CVEs in Python deps
    │
    └── Job: docker (parallel)
        ├── docker build              ← Image builds successfully
        └── Trivy scan                ← Container image CVEs
```

### Why No `terraform plan` in CI?

`terraform plan` requires cloud credentials (AWS/GCP). CI doesn't have them by default. Options:

1. **Current approach**: `validate` catches syntax and type errors without credentials.
2. **Future improvement**: Set up GitHub OIDC federation (see `docs/secrets-management.md`) to give CI short-lived AWS credentials. Then add `plan` back.

### Checkov: Policy-as-Code

Checkov scans Terraform files for security misconfigurations:
- Public S3 buckets
- Unencrypted storage
- Overly permissive IAM policies
- Missing logging
- Network exposure

`.checkov.yaml` contains the skip list with rationale for each suppressed check. This is the answer to "what prevents someone from adding `0.0.0.0/0` to a security group and getting it merged?" — Checkov fails the PR.

### Trivy: Container Scanning

Trivy scans the built Docker image for:
- OS package CVEs (Debian packages)
- Python package CVEs (installed pip packages)

`.trivyignore` contains CVEs that have no available fix (`will_not_fix`) or are mitigated by our usage pattern (e.g., duckdb CVE only exploitable with untrusted input; we control all input).

### Dependabot

Automated weekly PRs for:
- Python dependency updates (in `dagster/`)
- GitHub Actions version updates (in `.github/workflows/`)

This ensures you don't fall behind on security patches.

---

## Dependency Management

### The Lockfile (`dagster/uv.lock`)

`uv.lock` pins every transitive dependency to an exact version with hashes. This means:

- **Reproducible builds**: Same versions on every machine, every CI run.
- **Tamper detection**: If a package is modified after publishing, the hash won't match.
- **`uv sync --frozen`**: Fails if `pyproject.toml` has changed but the lockfile hasn't been regenerated. Catches "forgot to update the lockfile" errors in CI.

### Updating Dependencies

```bash
# Update lockfile after changing pyproject.toml
make lock          # runs: cd dagster && uv lock

# Check for known CVEs
make audit-deps    # runs: cd dagster && uv run pip-audit
```

### Pre-commit Hooks (`.pre-commit-config.yaml`)

Run automatically before each `git commit`:

| Hook | What it catches |
|------|----------------|
| `terraform-fmt` | Unformatted Terraform |
| `tflint` | Terraform linting errors |
| `yamllint --strict` | Invalid YAML (including table templates) |
| `ruff` | Python lint issues (auto-fixes some) |
| `ruff-format` | Python formatting |
| `checkov` | Security misconfigurations in Terraform |

---

## Compliance Architecture

### SOC2 Control Matrix

| What an auditor asks | Where the answer is |
|---------------------|-------------------|
| "How do you control access?" | Three-tier IAM roles + Lake Formation column exclusion (`aws/modules/iam/`) |
| "Is data encrypted?" | SSE-KMS at rest (`aws/modules/storage/main.tf`), TLS in transit (bucket policy) |
| "Do you have audit logs?" | CloudTrail data events → audit bucket, 7-year retention (`aws/modules/storage/cloudtrail.tf`) |
| "How do you detect changes?" | Schema drift sensor + Dagster audit logging (`dagster/lakehouse/sensors/`) |
| "Is infrastructure version-controlled?" | Git + Terraform + CI/CD (`aws/`, `.github/workflows/ci.yml`) |
| "How do you enforce security in code changes?" | Checkov in CI + pre-commit (`.checkov.yaml`, `.pre-commit-config.yaml`) |

### HIPAA Relevant Controls

| Requirement | Implementation |
|-------------|---------------|
| **§164.312(a)** Access control | IAM roles + Lake Formation + Dagster PII masking |
| **§164.312(b)** Audit controls | CloudTrail (7-year retention), Dagster structured audit logs |
| **§164.312(c)** Integrity | S3 versioning + Iceberg snapshots (immutable history) |
| **§164.312(e)** Transmission security | TLS enforcement on S3 bucket policy + ALB TLS 1.3 |

### What This Repo Doesn't Cover

- **Administrative safeguards**: Security training, workforce policies, business associate agreements
- **Physical safeguards**: AWS/GCP handle these (data center security)
- **Incident response procedures**: `docs/operations-runbook.md` is a starting point but your organization needs its own plan
- **Penetration testing**: Should be done by a qualified firm against your deployed environment

---

## Secrets Management

Full guide: `docs/secrets-management.md`. Key principles:

### Local Development

Use `.env` files (gitignored). Never commit real credentials.

```bash
cp dagster/.env.example dagster/.env
# Edit with your values
```

Use `aws-vault` or `granted` for AWS credential isolation — they store credentials in your OS keychain, not on disk.

### Production

| Secret Type | Where to Store | Why |
|-------------|---------------|-----|
| Database passwords | AWS Secrets Manager | Auto-rotation, audit trail, per-secret IAM |
| Config values (endpoints, flags) | SSM Parameter Store | Free tier, simple, versioned |
| Nessie tokens | Secrets Manager | Rotation support |

### CI/CD

**GitHub OIDC federation** instead of static AWS access keys:

```yaml
# GitHub Actions
- uses: aws-actions/configure-aws-credentials@v4
  with:
    role-to-assume: arn:aws:iam::ACCOUNT:role/github-ci
    aws-region: us-east-1
```

GitHub issues a short-lived JWT. AWS trusts it via OIDC. No static keys to rotate or leak.

---

## Networking

Only created when `catalog_type = "nessie"` (Glue needs no networking).

```
VPC (10.0.0.0/16)
├── Public Subnet 1 (10.0.0.0/24, AZ-a)
│   └── ALB, Internet Gateway route
├── Public Subnet 2 (10.0.1.0/24, AZ-b)
│   └── NAT Gateway (single, cost optimization)
├── Private Subnet 1 (10.0.10.0/24, AZ-a)
│   └── ECS Fargate tasks, route to NAT
└── Private Subnet 2 (10.0.11.0/24, AZ-b)
    └── ECS Fargate tasks, route to NAT
```

**Why private subnets for ECS?** Nessie has no built-in authentication. If tasks were in public subnets with public IPs, anyone could query the catalog API. Private subnets + internal ALB = only reachable from within the VPC (or via VPN/peering).

**Why single NAT gateway?** Each NAT gateway costs ~$32/month + data transfer. For HA, you'd need one per AZ ($64/month). Single NAT is a cost tradeoff — if the NAT's AZ goes down, ECS tasks in the other AZ lose internet access. Acceptable for dev; upgrade for production.

**Security groups:**

| Group | Ingress | Egress |
|-------|---------|--------|
| ALB | Port 80/443 from `nessie_allowed_cidrs` (default: `10.0.0.0/8`) | All (health checks, responses) |
| ECS | Port 19120 from ALB security group only | All (pull images, reach AWS APIs, DynamoDB) |

---

## Cost Model

### AWS Glue Path (Cheapest)

| Resource | Monthly Cost |
|----------|-------------|
| S3 storage | ~$0.023/GB (Standard), ~$0.0125/GB (IA) |
| Athena queries | $5/TB scanned |
| CloudTrail | $2/100K data events |
| Glue catalog | Free (first million objects) |
| **Total (10GB data)** | **~$1-5/month** |

### AWS Nessie Path

| Resource | Monthly Cost |
|----------|-------------|
| Everything above | $1-5 |
| ECS Fargate (0.5 vCPU, 1GB) | ~$15-20 |
| NAT Gateway | ~$32 + data transfer |
| ALB | ~$16 + LCU charges |
| DynamoDB (on-demand) | ~$0-5 (depends on write volume) |
| **Total** | **~$65-80/month** |

### GCP BigLake Path

| Resource | Monthly Cost |
|----------|-------------|
| GCS storage | ~$0.020/GB (Standard), ~$0.010/GB (Nearline) |
| BigQuery queries | $5/TB scanned |
| **Total (10GB data)** | **~$1-5/month** |

---

## Key Design Tradeoffs

### 1. AWS-Managed Encryption vs Customer-Managed Keys (CMK)

**Chose**: AWS-managed by default, CMK optional.

| | AWS-Managed | CMK |
|---|---|---|
| **Cost** | Free | $1/key/month + $0.03/10K API calls |
| **Control** | AWS manages rotation | You control rotation, deletion, access |
| **Risk** | None (AWS can't lose the key) | Key deletion = permanent data loss |
| **Compliance** | Sufficient for most SOC2 | Required by some HIPAA interpretations |

**When to upgrade**: If your compliance team specifically requires CMK, set `enable_cmek = true`.

### 2. Glue vs Nessie

| | Glue | Nessie |
|---|---|---|
| **Cost** | Free | $65-80/month |
| **Operations** | Zero (serverless) | Monitor ECS, health checks, DynamoDB |
| **Data branching** | No | Yes (Git-like) |
| **Vendor lock-in** | AWS-specific | Open source, portable |
| **Multi-engine** | Athena, Spark, EMR | Any REST-compatible engine |

**Default choice**: Glue. Switch to Nessie only if you need data branching.

### 3. Single NAT Gateway vs Multi-AZ NAT

**Chose**: Single NAT (saves ~$32/month).

**Risk**: If the NAT gateway's AZ fails, ECS tasks in the other AZ lose outbound internet. They can still receive traffic via the ALB (which is multi-AZ), but can't pull images or reach AWS APIs.

**When to upgrade**: Production environments where Nessie availability is critical. Add a second NAT gateway in the other public subnet.

### 4. HTTP by Default vs HTTPS Required

**Chose**: HTTP by default, HTTPS when `certificate_arn` is set.

**Why**: Requiring HTTPS means requiring an ACM certificate, which means requiring a domain name, which means blocking first-time setup. HTTP works for local dev and internal-only deployments.

**When to upgrade**: Always use HTTPS in production. Get a cert via ACM (free for public domains) and set `certificate_arn`.

### 5. Floating Docker Base Image vs Pinned

**Chose**: `python:3.11-slim` (floating) + `apt-get upgrade`.

| | Pinned (`3.11.11-slim`) | Floating (`3.11-slim`) |
|---|---|---|
| **Reproducibility** | Exact same image every build | May change between builds |
| **Security** | Must manually bump for patches | Gets latest patches automatically |
| **Staleness** | Gets stale fast | Always current |

**Why floating wins here**: The original pinned image had 18 unpatched CVEs. Docker images go stale in weeks. `apt-get upgrade` patches at build time regardless of base image tag.

---

## Failure Modes and How to Handle Them

### Nessie Unreachable

**Symptom**: Dagster jobs fail with connection refused.

**Check**: ECS service status → target group health → container logs.

**Common causes**: OOM (increase memory), DynamoDB throttling (check metrics), security group misconfiguration.

### Schema Drift Alert

**Symptom**: Sensor fires; table has unexpected columns.

**Response**: Determine if intentional (update YAML) or accidental (investigate CloudTrail, revert).

### Dagster OOM

**Symptom**: Container killed with exit code 137.

**Fix**: Increase memory limits in docker-compose or ECS task definition. For large datasets, process in chunks.

### S3 403 Forbidden

**Symptom**: Dagster or Athena gets AccessDenied.

**Check**: IAM role permissions → bucket policy → Lake Formation grants → VPC endpoint policies.

### Stale Lockfile

**Symptom**: CI fails at `uv sync --frozen`.

**Fix**: Run `make lock` locally and commit the updated `uv.lock`.

Full runbooks: `docs/operations-runbook.md`.

---

## Extending the System

### Adding a New Table

1. Create `table-templates/my_table.yaml` (copy an existing template)
2. `terraform apply` — creates the table in your catalog
3. Create `dagster/lakehouse/assets/my_table.py` — or add a `source:` block for auto-ingestion
4. Dagster picks it up automatically

### Adding a New Cloud Provider

1. Create `azure/` with the same module pattern (storage, catalog, iam)
2. Add `locals.tf` with `yamldecode()` for table templates
3. Add a new backend option in `dagster/lakehouse/resources/iceberg.py`
4. Dagster code doesn't change (PyIceberg abstracts the catalog)

### Adding New Quality Checks

1. Add a YAML file in `dagster/lakehouse/quality/soda_checks/`
2. Follow Soda's check syntax
3. The runner picks up all check files automatically

### Promoting to Production

1. Set up remote Terraform state (S3 + DynamoDB lock)
2. Create `environments/prod.tfvars` with production settings
3. Enable `certificate_arn` for HTTPS on Nessie
4. Set `nessie_min_count = 2` for HA
5. Set `alarm_sns_topic_arn` for monitoring
6. Configure GitHub OIDC for CI/CD credentials
7. Review the production hardening checklist in `docs/compliance.md`
