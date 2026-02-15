"""Feature table assets for ML feature store."""

import pyarrow as pa
from dagster import AssetExecutionContext, asset

from lakehouse.utils.table_loader import get_template

_template = get_template("feature_table")


@asset(
    key_prefix=["lakehouse"],
    metadata={"namespace": _template["namespace"]},
    description=_template["description"],
    tags=_template.get("tags", {}),
)
def feature_table(context: AssetExecutionContext) -> pa.Table:
    """Compute and write ML features.

    In production, replace this stub with your feature computation logic
    (SQL transforms, pandas/Polars pipelines, model inference, etc.).
    """
    context.log.info("Processing feature_table asset")

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
