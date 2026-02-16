"""Auto-generated assets for templates with a `source` block.

When a table template includes a `source` key, this module generates a Dagster
asset that reads files from the declared path (S3/GCS) and writes them to the
corresponding Iceberg table via the IO manager.

Templates without `source` are skipped — those use hand-written stub assets.
"""

import pyarrow as pa
import pyarrow.dataset as pad
from dagster import AssetExecutionContext, RetryPolicy, asset

from lakehouse.utils.audit import log_audit_event
from lakehouse.utils.table_loader import (
    iceberg_type_to_arrow,
    load_table_templates,
)

_ALLOWED_SCHEMES = ("s3://", "gs://")


def _build_schema(template: dict) -> pa.Schema:
    """Build a PyArrow schema from a table template's column definitions."""
    return pa.schema(
        [pa.field(col["name"], iceberg_type_to_arrow(col["type"])) for col in template["columns"]]
    )


def _read_source(source: dict, schema: pa.Schema) -> pa.Table:
    """Read files from a source path and return a PyArrow table.

    Supports parquet, csv, and json formats. S3 (s3://) and GCS (gs://)
    paths work natively via PyArrow's built-in filesystem layer.
    """
    path = source["path"]
    if not any(path.startswith(scheme) for scheme in _ALLOWED_SCHEMES):
        raise ValueError(
            f"Source path must start with one of {_ALLOWED_SCHEMES}, got: {path!r}. "
            "Local and arbitrary file paths are not allowed for security reasons."
        )
    fmt = source.get("format", "parquet")

    if fmt == "parquet":
        ds = pad.dataset(path, format="parquet", schema=schema)
    elif fmt == "csv":
        csv_options = source.get("csv_options", {})
        from pyarrow.csv import ConvertOptions, ReadOptions

        read_opts = ReadOptions(
            column_names=csv_options.get("column_names"),
            skip_rows=csv_options.get("skip_rows", 0),
        )
        convert_opts = ConvertOptions(column_types=schema)
        csv_format = pad.CsvFileFormat(
            read_options=read_opts,
            convert_options=convert_opts,
        )
        if "delimiter" in csv_options:
            from pyarrow.csv import ParseOptions

            parse_opts = ParseOptions(delimiter=csv_options["delimiter"])
            csv_format = pad.CsvFileFormat(
                read_options=read_opts,
                convert_options=convert_opts,
                parse_options=parse_opts,
            )
        ds = pad.dataset(path, format=csv_format)
    elif fmt == "json":
        ds = pad.dataset(path, format="json")
    else:
        raise ValueError(f"Unsupported source format: {fmt!r}. Use 'parquet', 'csv', or 'json'.")

    table = ds.to_table()

    # Cast to declared schema for json (which doesn't enforce schema on read)
    if fmt == "json" and table.schema != schema:
        table = table.cast(schema)

    return table


def _make_source_asset(template_name: str, template: dict):
    """Create a Dagster @asset for a template with a source block."""
    source = template["source"]
    schema = _build_schema(template)

    @asset(
        name=template["name"],
        key_prefix=["lakehouse"],
        metadata={"namespace": template["namespace"]},
        description=template.get("description", ""),
        tags=template.get("tags", {}),
        retry_policy=RetryPolicy(max_retries=2, delay=30),
        op_tags={"dagster/max_runtime": 3600},
    )
    def _source_asset(context: AssetExecutionContext) -> pa.Table:
        context.log.info(f"Reading {source.get('format', 'parquet')} data from {source['path']}")
        table = _read_source(source, schema)
        context.log.info(f"Read {table.num_rows} rows, {table.num_columns} columns")
        log_audit_event(
            "source_ingest",
            template["name"],
            details={
                "source_path": source["path"],
                "format": source.get("format", "parquet"),
                "row_count": table.num_rows,
                "column_count": table.num_columns,
            },
        )
        return table

    return _source_asset


def build_source_assets() -> list:
    """Build assets for all templates that have a `source` block."""
    templates = load_table_templates()
    assets = []
    for name, template in templates.items():
        if "source" in template:
            assets.append(_make_source_asset(name, template))
    return assets


source_ingestion_assets = build_source_assets()
