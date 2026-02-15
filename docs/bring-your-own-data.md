# Bring Your Own Data

You have data files sitting in S3 or GCS. You want them in Iceberg tables — queryable in Athena or BigQuery, with schema evolution, time-travel, and governance. This guide shows you how.

## Two Paths

| Approach | When to use | Effort |
|----------|------------|--------|
| **Source block** (this guide) | Your data is already in Parquet, CSV, or JSON files in object storage | Add 2-3 lines to YAML |
| **Custom Python asset** | You need CDC merges, API calls, joins, or complex transforms | Write a Python function |

Most teams start with source blocks for their raw/staging tables, then write custom assets for transformed/enriched tables downstream.

## Step-by-Step: Your First Table

### 1. Define the table in YAML

Create a new file in `table-templates/` (or edit an existing one). Add a `source` block that points to your files:

```yaml
# table-templates/web_events.yaml
name: web_events
namespace: lakehouse
description: Raw web analytics events from Firehose

columns:
  - name: event_id
    type: string
    required: true
  - name: event_type
    type: string
  - name: event_timestamp
    type: timestamptz
    required: true
  - name: user_id
    type: string
    pii: true
    access_level: restricted
  - name: page_url
    type: string
  - name: payload
    type: string

partition_spec:
  - column: event_timestamp
    transform: day

properties:
  write_format: parquet
  history_expire_max_snapshot_age_ms: 604800000  # 7 days

tags:
  domain: analytics

# This is the key part — point at your data:
source:
  path: s3://my-raw-bucket/web-events/
  format: parquet
```

### 2. Create the Iceberg table with Terraform

```bash
cd aws   # or: cd gcp
terraform plan    # Preview — you'll see the new table in Glue/BigLake
terraform apply   # Create it
```

Terraform reads the YAML and registers the table in your catalog. The `source` block is ignored by Terraform — it's only used by Dagster.

### 3. Start Dagster and materialize

```bash
cd dagster
source .venv/bin/activate
dagster dev
```

Open http://localhost:3000. You'll see a new `web_events` asset in the graph — auto-generated from the `source` block. Click it and hit **Materialize**. Dagster reads the Parquet files from S3 and writes them to the Iceberg table.

### 4. Query your data

```sql
-- In Athena (AWS Glue path):
SELECT event_type, COUNT(*) as cnt
FROM lakehouse.web_events
WHERE event_timestamp >= TIMESTAMP '2024-01-01 00:00:00'
GROUP BY event_type
ORDER BY cnt DESC;
```

That's it. No Python code required.

## Supported Formats

### Parquet (recommended)

The default. Parquet files are columnar, compressed, and self-describing. If your data is already in Parquet (e.g., from Firehose, Spark, or dbt), this is the simplest path.

```yaml
source:
  path: s3://my-bucket/data/
  format: parquet
```

Schema enforcement happens on read — PyArrow checks that file columns match the declared types.

### CSV

```yaml
source:
  path: s3://my-bucket/exports/
  format: csv
  csv_options:
    delimiter: ","      # default; use "\t" for TSV, "|" for pipe-delimited
    skip_rows: 1        # skip header row (default: 0)
```

If your CSV files don't have a header row, provide column names explicitly:

```yaml
source:
  path: s3://my-bucket/exports/
  format: csv
  csv_options:
    column_names: [id, name, email, created_at]
```

#### CSV gotchas

- **Timestamps**: CSV has no native timestamp type. PyArrow will attempt to parse strings as timestamps based on the declared column type. ISO 8601 format (`2024-01-15T10:30:00Z`) works best.
- **Encoding**: PyArrow expects UTF-8. If your files use Latin-1 or another encoding, convert them first.
- **Quoting**: Fields containing the delimiter must be quoted. PyArrow follows RFC 4180 by default.
- **Large files**: CSV reads are slower than Parquet because the entire file must be parsed. For production workloads, consider converting to Parquet first.

### JSON (newline-delimited)

```yaml
source:
  path: s3://my-bucket/api-responses/
  format: json
```

Expects newline-delimited JSON (one JSON object per line, `.jsonl` / `.ndjson` format). The data is cast to your declared schema after reading.

## Examples by Use Case

### Events from Firehose (Parquet in S3)

Amazon Kinesis Firehose writes Parquet files to S3 with a date-based prefix structure:

```yaml
source:
  path: s3://my-firehose-bucket/events/
  format: parquet
```

PyArrow reads all `.parquet` files under the path recursively.

### Database exports (CSV)

Many databases export to CSV. A nightly `pg_dump` or Salesforce export:

```yaml
source:
  path: s3://my-exports-bucket/customers/
  format: csv
  csv_options:
    delimiter: ","
    skip_rows: 1
```

### API responses (JSON)

If you land API responses as JSONL files:

```yaml
source:
  path: gs://my-gcs-bucket/api-data/
  format: json
```

### GCS instead of S3

Just use the `gs://` prefix:

```yaml
source:
  path: gs://my-gcs-bucket/events/
  format: parquet
```

PyArrow's built-in GCS filesystem handles authentication via the standard `GOOGLE_APPLICATION_CREDENTIALS` or Application Default Credentials.

## When to Write Custom Python

Source blocks handle the common case: "read files, write to Iceberg." For anything more complex, write a custom asset:

| Scenario | Why a source block isn't enough |
|----------|-------------------------------|
| **CDC / SCD2 merges** | You need to compare new vs. existing rows, close old records, insert new versions |
| **API ingestion** | Data comes from an HTTP API, not files in storage |
| **Joins / enrichment** | The asset depends on other assets (Dagster dependency graph) |
| **ML feature computation** | Feature logic is Python code (aggregations, model inference) |
| **Deduplication** | Files contain duplicates that need to be resolved |
| **Schema mapping** | Source column names don't match your table schema |

See the [Table Template Reference](table-template-reference.md#adding-your-own-table) for how to write a custom asset.

## FAQ

### Can I use both source blocks and custom assets?

Yes, but not for the same table. Each table template either has a `source` block (auto-generated asset) or doesn't (you write the asset manually). You can have some tables with source blocks and others with custom Python — they coexist in the same Dagster deployment.

### What if my file columns don't match the YAML schema?

For **Parquet**, the schema is enforced on read. If a column is missing or has the wrong type, you'll get a clear error at materialization time. For **JSON**, data is cast to the declared schema — compatible type conversions (e.g., int to double) work, but incompatible ones fail. For **CSV**, all data is parsed as the declared types.

### How do I do incremental loads?

Source blocks use a **full-refresh** model: each materialization reads all files at the path and overwrites the table. This is simple and correct for most batch use cases.

For incremental loads (only process new files since last run), you'll need a custom Python asset that tracks state. This is a good candidate for a follow-up enhancement.

### What credentials does Dagster need to read my files?

The same AWS/GCP credentials used by the IO manager to write to Iceberg tables. No new environment variables or configuration needed — see the [Configuration Reference](configuration-reference.md#dagster-environment-variables).

### What if my path has millions of files?

PyArrow's dataset API handles large file sets efficiently — it uses metadata to plan the scan before reading data. However, the full-refresh model means every materialization reads all files. For very large datasets, consider partitioning your source files into date-based prefixes and adjusting the `path` to point at a recent subset.
