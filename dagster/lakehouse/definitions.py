"""Dagster definitions entry point."""

from dagster import Definitions, load_assets_from_modules

from lakehouse.assets import dimensions, event_streams, features
from lakehouse.resources.iceberg import iceberg_io_manager
from lakehouse.sensors.schema_drift import schema_drift_sensor

all_assets = load_assets_from_modules([event_streams, dimensions, features])

defs = Definitions(
    assets=all_assets,
    resources={
        "io_manager": iceberg_io_manager,
    },
    sensors=[schema_drift_sensor],
)
