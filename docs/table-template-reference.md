# Table Template Reference

Table templates are YAML files in `table-templates/` that serve as the single source of truth for both Terraform infrastructure and Dagster pipelines.

## Schema

See `table-templates/_schema.json` for the full JSON Schema. Key fields:

### Required Fields

| Field | Type | Description |
|-------|------|-------------|
| `name` | string | Table name (snake_case) |
| `namespace` | string | Catalog namespace / database name |
| `columns` | array | Column definitions |
| `partition_spec` | array | Iceberg partition specification |
| `properties` | object | Table properties |

### Column Definition

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `name` | string | (required) | Column name (snake_case) |
| `type` | string | (required) | Iceberg type (see below) |
| `required` | boolean | false | Whether the column is required (NOT NULL) |
| `description` | string | | Human-readable description |
| `pii` | boolean | false | Contains personally identifiable information |
| `access_level` | string | "public" | One of: public, internal, restricted |

### Supported Iceberg Types

| Type | Description |
|------|-------------|
| `boolean` | True/false |
| `int` | 32-bit signed integer |
| `long` | 64-bit signed integer |
| `float` | 32-bit IEEE 754 |
| `double` | 64-bit IEEE 754 |
| `date` | Calendar date |
| `time` | Time of day |
| `timestamp` | Timestamp without timezone |
| `timestamptz` | Timestamp with timezone |
| `string` | UTF-8 string |
| `uuid` | UUID |
| `binary` | Arbitrary bytes |

### Partition Spec

Each entry specifies a column and an Iceberg partition transform:

| Transform | Example | Description |
|-----------|---------|-------------|
| `identity` | `identity` | Partition by exact value |
| `year` | `year` | Extract year from date/timestamp |
| `month` | `month` | Extract year-month |
| `day` | `day` | Extract date |
| `hour` | `hour` | Extract date-hour |
| `bucket[N]` | `bucket[16]` | Hash into N buckets |
| `truncate[N]` | `truncate[4]` | Truncate to width N |

### Properties

| Property | Type | Description |
|----------|------|-------------|
| `write_format` | string | parquet, orc, or avro (default: parquet) |
| `history_expire_max_snapshot_age_ms` | integer | Time-travel retention in ms |

Additional properties are allowed and passed through to Iceberg table properties.

### Tags

Free-form key-value pairs for organizational metadata:

```yaml
tags:
  domain: analytics
  pattern: append-only
```

## Example

```yaml
name: event_stream
namespace: lakehouse
description: Append-only event stream

columns:
  - name: event_id
    type: string
    required: true
  - name: user_id
    type: string
    pii: true
    access_level: restricted

partition_spec:
  - column: event_timestamp
    transform: day

properties:
  write_format: parquet
  history_expire_max_snapshot_age_ms: 604800000

tags:
  domain: analytics
```

## How Templates Are Used

### Terraform
`locals.tf` reads all `*.yaml` files via `yamldecode(file(...))` and passes them to modules:
- **Catalog modules** register table shells with the correct schema
- **IAM modules** use `access_level` to configure column-level permissions

### Dagster
`utils/table_loader.py` reads templates and:
- Assets use column definitions to build PyArrow schemas
- Schema drift sensor compares live schemas against template definitions
