"""Tests for table_loader utility."""

import tempfile
from pathlib import Path

import pytest
import yaml

import pyarrow as pa

from lakehouse.utils.table_loader import (
    get_column_names,
    get_restricted_columns,
    get_template,
    iceberg_type_to_arrow,
    load_table_templates,
)


@pytest.fixture(autouse=True)
def _clear_cache():
    """Clear lru_cache between tests."""
    load_table_templates.cache_clear()
    yield
    load_table_templates.cache_clear()


def test_load_all_templates():
    """All 3 templates load successfully."""
    templates = load_table_templates()
    assert len(templates) == 3
    assert set(templates.keys()) == {"event_stream", "scd_type2", "feature_table"}


def test_get_template_event_stream():
    """Event stream template has expected structure."""
    t = get_template("event_stream")
    assert t["name"] == "event_stream"
    assert t["namespace"] == "lakehouse"
    assert len(t["columns"]) > 0
    assert len(t["partition_spec"]) > 0


def test_get_template_scd_type2():
    """SCD Type 2 template loads correctly."""
    t = get_template("scd_type2")
    assert t["name"] == "scd_type2"


def test_get_template_feature_table():
    """Feature table template loads correctly."""
    t = get_template("feature_table")
    assert t["name"] == "feature_table"


def test_get_template_not_found():
    """Nonexistent template raises KeyError with helpful message."""
    with pytest.raises(KeyError, match="not found"):
        get_template("nonexistent_table")


def test_get_restricted_columns():
    """Restricted columns are correctly identified."""
    t = get_template("event_stream")
    restricted = get_restricted_columns(t)
    assert "user_id" in restricted
    assert "ip_address" in restricted
    assert "event_id" not in restricted


def test_get_restricted_columns_feature_table():
    """Feature table has no restricted columns."""
    t = get_template("feature_table")
    restricted = get_restricted_columns(t)
    assert restricted == []


def test_get_column_names():
    """Column names extraction works."""
    t = get_template("event_stream")
    names = get_column_names(t)
    assert "event_id" in names
    assert "event_timestamp" in names


def test_empty_yaml_raises():
    """Empty YAML file raises ValueError."""
    with tempfile.TemporaryDirectory() as tmpdir:
        empty_file = Path(tmpdir) / "empty.yaml"
        empty_file.write_text("")
        with pytest.raises(ValueError, match="Empty YAML"):
            load_table_templates(Path(tmpdir))


def test_missing_keys_raises():
    """YAML missing required keys raises ValueError."""
    with tempfile.TemporaryDirectory() as tmpdir:
        bad_file = Path(tmpdir) / "bad.yaml"
        bad_file.write_text(yaml.dump({"name": "test"}))
        with pytest.raises(ValueError, match="missing required keys"):
            load_table_templates(Path(tmpdir))


class TestIcebergTypeToArrow:
    """Tests for the iceberg_type_to_arrow mapping."""

    @pytest.mark.parametrize(
        "iceberg_type, expected",
        [
            ("boolean", pa.bool_()),
            ("int", pa.int32()),
            ("long", pa.int64()),
            ("float", pa.float32()),
            ("double", pa.float64()),
            ("date", pa.date32()),
            ("time", pa.time64("us")),
            ("timestamp", pa.timestamp("us")),
            ("timestamptz", pa.timestamp("us", tz="UTC")),
            ("string", pa.string()),
            ("uuid", pa.string()),
            ("binary", pa.binary()),
        ],
    )
    def test_known_types(self, iceberg_type, expected):
        assert iceberg_type_to_arrow(iceberg_type) == expected

    def test_unknown_type_falls_back_to_string(self):
        assert iceberg_type_to_arrow("decimal(10,2)") == pa.string()
        assert iceberg_type_to_arrow("unknown") == pa.string()
