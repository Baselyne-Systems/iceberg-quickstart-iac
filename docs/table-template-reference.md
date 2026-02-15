# Table Template Reference

## What Are Table Templates?

Table templates are YAML files in `table-templates/` that describe your Iceberg tables — their columns, types, partitioning strategy, and access controls. They're the **single source of truth** that both Terraform (infrastructure) and Dagster (pipelines) read from.

**Why YAML?** It's human-readable, easy to review in pull requests, and can be consumed by both HCL (Terraform's language) and Python (Dagster's language) without custom tooling.

## Quick Example

Here's a minimal table template with annotations:

```yaml
# table-templates/orders.yaml

name: orders                    # Table name (used in SQL: SELECT * FROM lakehouse.orders)
namespace: lakehouse            # Database/catalog namespace
description: Customer orders    # Human-readable description

columns:
  - name: order_id              # Column name
    type: string                # Data type (see full list below)
    required: true              # NOT NULL constraint
    description: Unique order identifier

  - name: customer_email
    type: string
    pii: true                   # Flag: this column has personally identifiable info
    access_level: restricted    # Only writer/admin roles can see this column

  - name: order_total
    type: double
    description: Order total in USD

  - name: created_at
    type: timestamptz
    required: true

# How data is physically organized on disk for faster queries
partition_spec:
  - column: created_at
    transform: day              # One folder per day (2024-01-15, 2024-01-16, ...)

# Default sort within each partition (helps with query performance)
sort_order:
  - column: order_id
    direction: asc

# Iceberg table properties
properties:
  write_format: parquet                          # File format (parquet is the standard)
  history_expire_max_snapshot_age_ms: 604800000  # Keep 7 days of time-travel history

# Free-form metadata tags
tags:
  domain: commerce
  pattern: append-only
```

## Full Schema Reference

### Top-Level Fields

| Field | Required | Type | Description | Example |
|-------|----------|------|-------------|---------|
| `name` | Yes | string | Table name in snake_case. Used in SQL queries and file paths. | `event_stream` |
| `namespace` | Yes | string | Catalog namespace (like a database name). All tables in this template use the same namespace. | `lakehouse` |
| `description` | No | string | What this table contains. Shows up in catalog UIs and documentation. | `Append-only clickstream events` |
| `columns` | Yes | array | List of column definitions (see below). | |
| `partition_spec` | Yes | array | How data is physically partitioned (see below). Can be empty `[]` for unpartitioned tables. | |
| `sort_order` | No | array | Default sort order within partitions. | |
| `properties` | Yes | object | Iceberg table properties. | |
| `tags` | No | object | Free-form key-value metadata. | `{domain: analytics}` |

### Column Definition

Each column has these fields:

| Field | Required | Type | Default | Description |
|-------|----------|------|---------|-------------|
| `name` | Yes | string | | Column name in snake_case |
| `type` | Yes | string | | Data type (see "Supported Types" below) |
| `required` | No | boolean | `false` | If `true`, the column cannot be null |
| `description` | No | string | | What this column contains |
| `pii` | No | boolean | `false` | Does this column contain personally identifiable information? (Used for governance tagging) |
| `access_level` | No | string | `"public"` | Who can read this column: `public` (everyone), `internal` (internal roles), or `restricted` (writer/admin only) |

#### Example: A Column With Governance Flags

```yaml
columns:
  - name: user_id
    type: string
    required: true
    description: The user who placed the order
    pii: true                   # Flagged as PII for compliance tracking
    access_level: restricted    # Hidden from the "reader" role

  - name: order_status
    type: string
    required: true
    description: Current order status (pending, shipped, delivered)
    # pii defaults to false, access_level defaults to "public"
    # → everyone can see this column
```

**What happens with `access_level: restricted`**:
- On **AWS**: The Terraform IAM module creates a Lake Formation grant that excludes this column from the reader role's SELECT permission
- On **GCP**: The column gets a Data Catalog policy tag that only writer/admin service accounts can read

### Supported Data Types

These map to standard [Iceberg types](https://iceberg.apache.org/spec/#schemas-and-data-types):

| Type | What it stores | SQL equivalent | Example value |
|------|---------------|---------------|---------------|
| `boolean` | True or false | `BOOLEAN` | `true` |
| `int` | Whole number (-2B to 2B) | `INT` / `INTEGER` | `42` |
| `long` | Large whole number | `BIGINT` | `9223372036854775807` |
| `float` | Decimal number (32-bit) | `FLOAT` | `3.14` |
| `double` | Decimal number (64-bit, more precise) | `DOUBLE` | `3.141592653589793` |
| `date` | Calendar date (no time) | `DATE` | `2024-01-15` |
| `time` | Time of day (no date) | `TIME` | `14:30:00` |
| `timestamp` | Date + time, no timezone | `TIMESTAMP` | `2024-01-15 14:30:00` |
| `timestamptz` | Date + time with timezone (UTC) | `TIMESTAMPTZ` | `2024-01-15T14:30:00Z` |
| `string` | Text of any length | `VARCHAR` / `STRING` | `"hello world"` |
| `uuid` | Universally unique identifier | `STRING` | `"550e8400-e29b-41d4-a716-446655440000"` |
| `binary` | Raw bytes | `BINARY` / `BYTES` | (binary data) |

### Partition Spec

Partitioning controls how data files are organized on disk. Good partitioning dramatically speeds up queries by letting the engine skip irrelevant files.

Each entry specifies a column and a **transform** — a function that extracts a partition value:

| Transform | What it does | Example input | Partition value | Use when |
|-----------|-------------|---------------|-----------------|----------|
| `identity` | Use the value as-is | `"us-east-1"` | `us-east-1` | Low-cardinality columns (region, status) |
| `year` | Extract the year | `2024-06-15 10:30:00` | `2024` | Queries typically filter by year |
| `month` | Extract year + month | `2024-06-15 10:30:00` | `2024-06` | Queries typically filter by month |
| `day` | Extract the date | `2024-06-15 10:30:00` | `2024-06-15` | Queries typically filter by day (most common) |
| `hour` | Extract date + hour | `2024-06-15 10:30:00` | `2024-06-15-10` | Very high-volume data with hourly queries |
| `bucket[N]` | Hash into N buckets | `"user_12345"` | `7` (bucket 7 of 16) | High-cardinality columns you join on |
| `truncate[N]` | Truncate to width N | `"abcdef"` | `"abcd"` | String columns with common prefixes |

#### Example: Event Stream Partitioned by Day and Hour

```yaml
partition_spec:
  - column: event_timestamp
    transform: day      # First level: one folder per day
  - column: event_timestamp
    transform: hour     # Second level: within each day, one folder per hour
```

On disk, this creates a structure like:
```
s3://bucket/lakehouse/event_stream/
  event_timestamp_day=2024-01-15/
    event_timestamp_hour=10/
      data-00001.parquet
      data-00002.parquet
    event_timestamp_hour=11/
      data-00003.parquet
```

A query for `WHERE event_timestamp >= '2024-01-15 10:00:00'` only reads files in the `hour=10` folder, skipping everything else.

#### Example: Dimension Table Partitioned by Month

```yaml
partition_spec:
  - column: effective_from
    transform: month    # One folder per month — fewer partitions for slower-changing data
```

### Sort Order

Optional. Defines the default ordering of rows within each data file. Helps with:
- **Query performance**: Sorted data enables more efficient filtering and aggregation
- **Compression**: Similar values next to each other compress better

```yaml
sort_order:
  - column: entity_id
    direction: asc          # ascending (default)
    null_order: nulls_last  # where to put nulls (default: nulls_last)
  - column: feature_timestamp
    direction: desc         # most recent first
```

### Properties

Iceberg table properties that control storage and maintenance behavior:

| Property | Type | Default | Description |
|----------|------|---------|-------------|
| `write_format` | string | `"parquet"` | File format. Parquet is recommended for most use cases. Alternatives: `orc`, `avro` |
| `history_expire_max_snapshot_age_ms` | integer | (none) | How long to keep old snapshots for time-travel queries. Set in milliseconds. |

Common time-travel values:
| Duration | Milliseconds |
|----------|-------------|
| 1 day | `86400000` |
| 7 days | `604800000` |
| 30 days | `2592000000` |
| 90 days | `7776000000` |

You can add any additional Iceberg table properties — they're passed through as-is. See the [Iceberg configuration reference](https://iceberg.apache.org/docs/latest/configuration/) for the full list.

### Tags

Free-form key-value pairs for organizational metadata. Not used by Iceberg itself, but useful for:
- Filtering tables in dashboards
- Grouping by domain or team
- Documenting the data pattern

```yaml
tags:
  domain: analytics       # Which team/domain owns this table
  pattern: append-only    # Data loading pattern
  owner: data-eng         # Responsible team
  sla: tier-1             # Service level agreement
```

## Included Templates

This repo ships with three templates that cover common data patterns:

### `event_stream.yaml` — Append-Only Events

**Pattern**: New rows are always appended; existing rows are never updated.
**Use case**: Clickstream, application logs, IoT sensor readings, transaction history.
**Partitioned by**: Day + hour (for high-volume, time-based queries).

### `scd_type2.yaml` — Slowly Changing Dimension Type 2

**Pattern**: When a record changes, the old version is "closed" (effective_to set, is_current=false) and a new version is inserted. Full history is preserved.
**Use case**: Customer records, product catalogs, employee directories — anything where you need to see "what did this record look like last month?"
**Partitioned by**: Month (based on effective_from date).

### `feature_table.yaml` — ML Feature Store

**Pattern**: Point-in-time feature values computed for entities (users, items, etc.). Supports time-travel for training data consistency.
**Use case**: ML feature engineering — store pre-computed features so training and serving use the same values.
**Partitioned by**: Day (based on feature_timestamp).

## Adding Your Own Table

1. Create a new YAML file in `table-templates/`:

```yaml
# table-templates/my_new_table.yaml
name: my_new_table
namespace: lakehouse
description: What this table contains

columns:
  - name: id
    type: string
    required: true
  - name: value
    type: double
  - name: created_at
    type: timestamptz
    required: true

partition_spec:
  - column: created_at
    transform: day

properties:
  write_format: parquet
  history_expire_max_snapshot_age_ms: 604800000
```

2. **Terraform picks it up automatically** — run `terraform plan` to see the new table registered in Glue/BigLake

3. **Create a Dagster asset** in `dagster/lakehouse/assets/`:

```python
# dagster/lakehouse/assets/my_new_table.py
import pyarrow as pa
from dagster import AssetExecutionContext, asset
from lakehouse.utils.table_loader import get_template

_template = get_template("my_new_table")

@asset(
    key_prefix=["lakehouse"],
    metadata={"namespace": _template["namespace"]},
    description=_template["description"],
)
def my_new_table(context: AssetExecutionContext) -> pa.Table:
    # Your data logic here
    ...
```

4. **Register the asset** in `dagster/lakehouse/definitions.py`:

```python
from lakehouse.assets import my_new_table

all_assets = load_assets_from_modules([event_streams, dimensions, features, my_new_table])
```

5. Optionally add a Soda check file in `dagster/lakehouse/quality/soda_checks/my_new_table_checks.yaml`

## Validating Templates

Use JSON Schema validation to check your YAML files:

```bash
# With pip install check-jsonschema
check-jsonschema --schemafile table-templates/_schema.json table-templates/my_new_table.yaml

# Or with yamllint for syntax
yamllint table-templates/
```
