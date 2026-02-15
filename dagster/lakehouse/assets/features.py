"""Feature table assets for ML feature store."""

import pyarrow as pa
from dagster import AssetExecutionContext, RetryPolicy, asset

from lakehouse.utils.table_loader import get_template, iceberg_type_to_arrow

_template = get_template("feature_table")


@asset(
    key_prefix=["lakehouse"],
    metadata={"namespace": _template["namespace"]},
    description=_template["description"],
    tags=_template.get("tags", {}),
    retry_policy=RetryPolicy(max_retries=2, delay=30),
    op_tags={"dagster/max_runtime": 3600},
)
def feature_table(context: AssetExecutionContext) -> pa.Table:
    """Compute and write ML features.

    In production, replace this stub with your feature computation logic
    (SQL transforms, pandas/Polars pipelines, model inference, etc.).
    """
    context.log.info("Processing feature_table asset")

    schema = pa.schema(
        [
            pa.field(col["name"], iceberg_type_to_arrow(col["type"]))
            for col in _template["columns"]
        ]
    )
    return pa.table({field.name: [] for field in schema}, schema=schema)
