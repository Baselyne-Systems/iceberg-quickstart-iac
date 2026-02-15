"""Schema drift sensor — compares live Iceberg schema against YAML templates."""

from datetime import datetime, timezone

from dagster import SensorEvaluationContext, sensor

from lakehouse.resources.iceberg import _get_catalog_config
from lakehouse.utils.alerting import alert
from lakehouse.utils.table_loader import get_column_names, load_table_templates

# Map Iceberg field type IDs to template type names for type-level comparison
_ICEBERG_TYPE_NAMES = {
    "boolean": "boolean",
    "int": "int",
    "long": "long",
    "float": "float",
    "double": "double",
    "date": "date",
    "time": "time",
    "timestamp": "timestamp",
    "timestamptz": "timestamptz",
    "string": "string",
    "uuid": "uuid",
    "binary": "binary",
    "fixed": "binary",
}


def _iceberg_type_to_template_type(iceberg_type) -> str:
    """Convert a PyIceberg type object to a template type string."""
    type_str = str(iceberg_type).lower()
    return _ICEBERG_TYPE_NAMES.get(type_str, type_str)


@sensor(minimum_interval_seconds=3600)
def schema_drift_sensor(context: SensorEvaluationContext):
    """Check for schema drift between YAML templates and live Iceberg tables.

    Runs hourly. Fires an alert if columns in the live table don't match the template.
    """
    from pyiceberg.catalog import load_catalog

    try:
        config = _get_catalog_config()
        catalog = load_catalog("lakehouse", **config)
    except Exception as e:
        context.log.warning("Could not connect to catalog: %s", e)
        return

    templates = load_table_templates()
    drift_found = False

    for name, template in templates.items():
        table_id = f"{template['namespace']}.{template['name']}"
        expected_columns = set(get_column_names(template))
        expected_types = {col["name"]: col["type"] for col in template["columns"]}

        try:
            table = catalog.load_table(table_id)
        except Exception:
            context.log.info("Table %s not found in catalog (may not be created yet)", table_id)
            continue

        live_columns = {field.name for field in table.schema().fields}
        live_types = {
            field.name: _iceberg_type_to_template_type(field.field_type)
            for field in table.schema().fields
        }

        missing = expected_columns - live_columns
        extra = live_columns - expected_columns

        # Check type mismatches on columns present in both
        type_mismatches = {}
        for col in expected_columns & live_columns:
            if col in live_types and col in expected_types:
                if live_types[col] != expected_types[col]:
                    type_mismatches[col] = {
                        "expected": expected_types[col],
                        "actual": live_types[col],
                    }

        if missing or extra or type_mismatches:
            drift_found = True
            msg = f"Schema drift detected in {table_id}."
            if missing:
                msg += f" Missing columns: {missing}."
            if extra:
                msg += f" Extra columns: {extra}."
            if type_mismatches:
                msg += f" Type mismatches: {type_mismatches}."

            context.log.warning(msg)
            alert("Schema Drift Detected", msg)

    # Update cursor with last successful check time
    context.update_cursor(datetime.now(timezone.utc).isoformat())

    if not drift_found:
        context.log.info("No schema drift detected across %d tables", len(templates))
