"""Schema drift sensor — compares live Iceberg schema against YAML templates."""

import os

from dagster import RunRequest, SensorEvaluationContext, sensor

from lakehouse.utils.alerting import alert
from lakehouse.utils.table_loader import get_column_names, load_table_templates


@sensor(minimum_interval_seconds=3600)
def schema_drift_sensor(context: SensorEvaluationContext):
    """Check for schema drift between YAML templates and live Iceberg tables.

    Runs hourly. Fires an alert if columns in the live table don't match the template.
    """
    from pyiceberg.catalog import load_catalog

    backend = os.environ.get("LAKEHOUSE_BACKEND", "aws-glue")

    try:
        if backend == "aws-glue":
            catalog = load_catalog(
                "lakehouse",
                type="glue",
                **{"s3.region": os.environ.get("AWS_REGION", "us-east-1")},
            )
        elif backend == "aws-nessie":
            catalog = load_catalog(
                "lakehouse",
                type="rest",
                uri=os.environ["NESSIE_URI"],
                **{"s3.region": os.environ.get("AWS_REGION", "us-east-1")},
            )
        elif backend == "gcp":
            catalog = load_catalog(
                "lakehouse",
                type="rest",
                uri=os.environ.get("ICEBERG_REST_URI", ""),
            )
        else:
            context.log.error("Unknown LAKEHOUSE_BACKEND: %s", backend)
            return
    except Exception as e:
        context.log.warning("Could not connect to catalog: %s", e)
        return

    templates = load_table_templates()
    drift_found = False

    for name, template in templates.items():
        table_id = f"{template['namespace']}.{template['name']}"
        expected_columns = set(get_column_names(template))

        try:
            table = catalog.load_table(table_id)
        except Exception:
            context.log.info("Table %s not found in catalog (may not be created yet)", table_id)
            continue

        live_columns = {field.name for field in table.schema().fields}

        missing = expected_columns - live_columns
        extra = live_columns - expected_columns

        if missing or extra:
            drift_found = True
            msg = f"Schema drift detected in {table_id}."
            if missing:
                msg += f" Missing columns: {missing}."
            if extra:
                msg += f" Extra columns: {extra}."

            context.log.warning(msg)
            alert("Schema Drift Detected", msg)

    if not drift_found:
        context.log.info("No schema drift detected across %d tables", len(templates))
