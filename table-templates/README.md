# Table Templates

Each YAML file in this directory defines an Iceberg table. Terraform creates the table in your cloud catalog; Dagster builds a data pipeline asset for it.

## Adding a New Table

### 1. Create the YAML file

Copy an existing template and modify it:

```bash
cp event_stream.yaml my_table.yaml
```

Every template needs these top-level fields:

```yaml
name: my_table               # snake_case — used in SQL and asset names
namespace: lakehouse          # catalog namespace / database
description: What this table contains

columns:
  - name: id
    type: string
    required: true
  - name: amount
    type: double
  - name: created_at
    type: timestamptz
    required: true

partition_spec:
  - column: created_at
    transform: day

properties:
  write_format: parquet
```

See [Table Template Reference](../docs/table-template-reference.md) for all available fields, types, and partition transforms.

### 2. Deploy the table

```bash
cd aws   # or: cd gcp
terraform plan    # Preview the new table
terraform apply   # Create it
```

### 3. Load data into it

You have two options:

#### Option A: Source block (no Python)

If your data already lives as files in S3 or GCS, add a `source` block to your YAML:

```yaml
# Parquet files
source:
  path: s3://my-bucket/raw-data/
  format: parquet

# CSV files
source:
  path: s3://my-bucket/exports/
  format: csv
  csv_options:
    delimiter: ","
    skip_rows: 1       # skip header row

# JSON (newline-delimited)
source:
  path: gs://my-bucket/api-data/
  format: json
```

Dagster auto-generates an asset that reads from this path and writes to Iceberg. No Python code needed. Start Dagster (`dagster dev`) and you'll see the new asset in the graph.

See [Bring Your Own Data](../docs/bring-your-own-data.md) for the full guide.

#### Option B: Custom Python asset

For complex logic (CDC merges, API calls, joins, ML features), write a Python asset:

```python
# dagster/lakehouse/assets/my_table.py
import pyarrow as pa
from dagster import AssetExecutionContext, asset
from lakehouse.utils.table_loader import get_template, iceberg_type_to_arrow

_template = get_template("my_table")

@asset(
    key_prefix=["lakehouse"],
    metadata={"namespace": _template["namespace"]},
    description=_template["description"],
    tags=_template.get("tags", {}),
)
def my_table(context: AssetExecutionContext) -> pa.Table:
    # Build schema from template
    schema = pa.schema([
        pa.field(col["name"], iceberg_type_to_arrow(col["type"]))
        for col in _template["columns"]
    ])

    # Your logic here — query an API, read a database, transform data, etc.
    data = {"id": ["abc"], "amount": [99.99], "created_at": ["2024-01-15T00:00:00Z"]}
    return pa.table(data, schema=schema)
```

Then register it in `dagster/lakehouse/definitions.py`:

```python
from lakehouse.assets import my_table

_stub_assets = load_assets_from_modules([event_streams, dimensions, features, my_table])
```

### 4. Validate your template (optional)

```bash
# With pip install check-jsonschema
check-jsonschema --schemafile _schema.json my_table.yaml
```

## Included Templates

| File | Pattern | Description |
|------|---------|-------------|
| `event_stream.yaml` | Append-only | Clickstream, logs, IoT events |
| `scd_type2.yaml` | Slowly Changing Dimension | Customer records, product catalogs (full history) |
| `feature_table.yaml` | Feature store | Pre-computed ML features |

## Supported Column Types

`boolean`, `int`, `long`, `float`, `double`, `date`, `time`, `timestamp`, `timestamptz`, `string`, `uuid`, `binary`

## Governance

Mark sensitive columns with `pii: true` and `access_level: restricted` to automatically exclude them from the reader IAM role:

```yaml
columns:
  - name: email
    type: string
    pii: true
    access_level: restricted
```
