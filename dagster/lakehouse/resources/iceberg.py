"""IO manager factory for Iceberg — returns the right catalog config based on LAKEHOUSE_BACKEND."""

import logging
import os

from dagster import IOManager, InputContext, OutputContext, io_manager
from tenacity import retry, stop_after_attempt, wait_exponential

from lakehouse.utils.audit import log_audit_event
from lakehouse.utils.table_loader import get_restricted_columns, load_table_templates

logger = logging.getLogger(__name__)


def _get_catalog_config() -> dict:
    """Build PyIceberg catalog config from environment."""
    backend = os.environ.get("LAKEHOUSE_BACKEND", "aws-glue")

    if backend == "aws-glue":
        return {
            "type": "glue",
            "s3.region": os.environ.get("AWS_REGION", "us-east-1"),
        }
    elif backend == "aws-nessie":
        return {
            "type": "rest",
            "uri": os.environ["NESSIE_URI"],
            "s3.region": os.environ.get("AWS_REGION", "us-east-1"),
        }
    elif backend == "gcp":
        return {
            "type": "rest",
            "uri": os.environ.get("ICEBERG_REST_URI", ""),
            "gcs.project-id": os.environ.get("GCP_PROJECT_ID", ""),
        }
    else:
        raise ValueError(f"Unknown LAKEHOUSE_BACKEND: {backend}")


class IcebergIOManager(IOManager):
    """Dagster IO manager that reads/writes Iceberg tables via PyIceberg."""

    @retry(stop=stop_after_attempt(3), wait=wait_exponential(multiplier=1, max=10), reraise=True)
    def __init__(self):
        from pyiceberg.catalog import load_catalog

        config = _get_catalog_config()
        self.catalog = load_catalog("lakehouse", **config)
        self._access_level = os.environ.get("LAKEHOUSE_ACCESS_LEVEL", "admin")

    def _table_name(self, context) -> str:
        namespace = context.metadata.get("namespace", "lakehouse")
        table = context.asset_key.path[-1]
        return f"{namespace}.{table}"

    def handle_output(self, context: OutputContext, obj) -> None:
        if obj is None:
            context.log.warning("Received None output, skipping write")
            return

        table_name = self._table_name(context)
        context.log.info("Writing to Iceberg table: %s", table_name)

        try:
            table = self.catalog.load_table(table_name)
        except Exception as e:
            if "NoSuchTableError" in type(e).__name__ or "NoSuchTable" in str(type(e)):
                raise RuntimeError(
                    f"Table '{table_name}' not found in catalog. "
                    "Have you run `terraform apply` to create it?"
                ) from e
            raise

        try:
            table.overwrite(obj)
        except Exception as e:
            live_cols = {f.name for f in table.schema().fields}
            obj_cols = set(obj.column_names) if hasattr(obj, "column_names") else set()
            if live_cols != obj_cols:
                context.log.error(
                    "Schema mismatch on write to %s. "
                    "Table columns: %s, Data columns: %s",
                    table_name,
                    sorted(live_cols),
                    sorted(obj_cols),
                )
            raise

        log_audit_event("table_write", table_name, details={
            "row_count": len(obj),
            "columns": list(obj.column_names) if hasattr(obj, "column_names") else [],
        })

        context.add_output_metadata(
            {
                "table": table_name,
                "num_rows": len(obj),
            }
        )

    def load_input(self, context: InputContext):
        table_name = self._table_name(context)
        context.log.info("Reading from Iceberg table: %s", table_name)

        try:
            table = self.catalog.load_table(table_name)
        except Exception as e:
            if "NoSuchTableError" in type(e).__name__ or "NoSuchTable" in str(type(e)):
                raise RuntimeError(
                    f"Table '{table_name}' not found in catalog. "
                    "Have you run `terraform apply` to create it?"
                ) from e
            raise

        result = table.scan().to_arrow()

        log_audit_event("table_read", table_name, details={
            "row_count": len(result),
            "access_level": self._access_level,
        })

        # PII masking: drop restricted columns for non-admin access
        if self._access_level == "reader":
            asset_name = context.asset_key.path[-1]
            templates = load_table_templates()
            template = templates.get(asset_name)
            if template:
                restricted = get_restricted_columns(template)
                cols_to_drop = [c for c in restricted if c in result.column_names]
                if cols_to_drop:
                    context.log.info(
                        "Access level 'reader': dropping restricted columns %s", cols_to_drop
                    )
                    log_audit_event("pii_columns_dropped", table_name, details={
                        "columns_dropped": cols_to_drop,
                        "access_level": self._access_level,
                    })
                    result = result.drop(cols_to_drop)

        return result


@io_manager
def iceberg_io_manager(_context):
    """Dagster IO manager resource for Iceberg tables."""
    return IcebergIOManager()
