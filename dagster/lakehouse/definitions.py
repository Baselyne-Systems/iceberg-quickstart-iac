"""Dagster definitions entry point."""

from dagster import Definitions, load_assets_from_modules

from lakehouse.assets import dimensions, event_streams, features
from lakehouse.assets.source_assets import source_ingestion_assets
from lakehouse.resources.iceberg import iceberg_io_manager
from lakehouse.sensors.schema_drift import schema_drift_sensor

_stub_assets = load_assets_from_modules([event_streams, dimensions, features])
all_assets = [*_stub_assets, *source_ingestion_assets]

defs = Definitions(
    assets=all_assets,
    resources={
        "io_manager": iceberg_io_manager,
    },
    sensors=[schema_drift_sensor],
)
