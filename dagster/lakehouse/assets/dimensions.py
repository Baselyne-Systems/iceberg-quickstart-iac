"""SCD Type 2 dimension assets."""

import pyarrow as pa
from dagster import AssetExecutionContext, RetryPolicy, asset

from lakehouse.utils.table_loader import get_template

_template = get_template("scd_type2")


@asset(
    key_prefix=["lakehouse"],
    metadata={"namespace": _template["namespace"]},
    description=_template["description"],
    tags=_template.get("tags", {}),
    retry_policy=RetryPolicy(max_retries=2, delay=30),
    op_tags={"dagster/max_runtime": 3600},
)
def scd_type2(context: AssetExecutionContext) -> pa.Table:
    """Process SCD Type 2 dimension updates.

    In production, replace this stub with your CDC / merge logic:
    1. Load current records from source
    2. Compare with existing dimension rows
    3. Close old records (set effective_to, is_current=false)
    4. Insert new/changed records with effective_from=now, is_current=true
    """
    context.log.info("Processing scd_type2 asset")

    schema = pa.schema(
        [
            pa.field(col["name"], _iceberg_to_arrow(col["type"]))
            for col in _template["columns"]
        ]
    )
    return pa.table({field.name: [] for field in schema}, schema=schema)


def _iceberg_to_arrow(iceberg_type: str) -> pa.DataType:
    mapping = {
        "boolean": pa.bool_(),
        "int": pa.int32(),
        "long": pa.int64(),
        "float": pa.float32(),
        "double": pa.float64(),
        "date": pa.date32(),
        "time": pa.time64("us"),
        "timestamp": pa.timestamp("us"),
        "timestamptz": pa.timestamp("us", tz="UTC"),
        "string": pa.string(),
        "uuid": pa.string(),
        "binary": pa.binary(),
    }
    return mapping.get(iceberg_type, pa.string())
