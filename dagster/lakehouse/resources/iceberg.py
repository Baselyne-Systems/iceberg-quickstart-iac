"""IO manager factory for Iceberg — returns the right catalog config based on LAKEHOUSE_BACKEND."""

import os

from dagster import IOManager, InputContext, OutputContext, io_manager
from pyiceberg.catalog import load_catalog


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

    def __init__(self):
        config = _get_catalog_config()
        self.catalog = load_catalog("lakehouse", **config)

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

        table = self.catalog.load_table(table_name)
        table.overwrite(obj)

        context.add_output_metadata(
            {
                "table": table_name,
                "num_rows": len(obj),
            }
        )

    def load_input(self, context: InputContext):
        table_name = self._table_name(context)
        context.log.info("Reading from Iceberg table: %s", table_name)

        table = self.catalog.load_table(table_name)
        return table.scan().to_arrow()


@io_manager
def iceberg_io_manager(_context):
    """Dagster IO manager resource for Iceberg tables."""
    return IcebergIOManager()
