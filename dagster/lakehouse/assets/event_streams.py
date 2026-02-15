"""Event stream assets — append-only tables."""

import pyarrow as pa
from dagster import AssetExecutionContext, RetryPolicy, asset

from lakehouse.utils.table_loader import get_template, iceberg_type_to_arrow

_template = get_template("event_stream")


@asset(
    key_prefix=["lakehouse"],
    metadata={"namespace": _template["namespace"]},
    description=_template["description"],
    tags=_template.get("tags", {}),
    retry_policy=RetryPolicy(max_retries=2, delay=30),
    op_tags={"dagster/max_runtime": 3600},
)
def event_stream(context: AssetExecutionContext) -> pa.Table:
    """Ingest event stream data.

    In production, replace this stub with your actual ingestion logic
    (Kafka consumer, S3 event notification, API pull, etc.).
    """
    context.log.info("Processing event_stream asset")

    # Stub: return empty table with correct schema
    schema = pa.schema(
        [
            pa.field(col["name"], iceberg_type_to_arrow(col["type"]))
            for col in _template["columns"]
        ]
    )
    return pa.table({field.name: [] for field in schema}, schema=schema)
