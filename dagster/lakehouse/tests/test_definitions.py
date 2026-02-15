"""Integration test — verify Dagster definitions load correctly."""

from lakehouse.definitions import defs


def test_definitions_load():
    """Definitions module imports and resolves without error."""
    assert defs is not None


def test_has_expected_assets():
    """At least three core assets are registered."""
    asset_keys = list(defs.resolve_asset_graph().get_all_asset_keys())
    assert len(asset_keys) >= 3
    names = {key.path[-1] for key in asset_keys}
    assert {"event_stream", "scd_type2", "feature_table"} <= names


def test_asset_keys_have_lakehouse_prefix():
    """All asset keys have the 'lakehouse' prefix."""
    for key in defs.resolve_asset_graph().get_all_asset_keys():
        assert key.path[0] == "lakehouse", f"Asset {key} missing 'lakehouse' prefix"


def test_has_sensor():
    """Schema drift sensor is registered."""
    sensors = defs.sensors
    assert len(sensors) == 1
    assert sensors[0].name == "schema_drift_sensor"


def test_has_io_manager():
    """Iceberg IO manager resource is registered."""
    assert "io_manager" in defs.resources
