"""Tests for source asset factory."""

import tempfile
from pathlib import Path
from unittest.mock import MagicMock, patch

import pyarrow as pa
import pytest
import yaml

from lakehouse.assets.source_assets import (
    _read_source,
    build_source_assets,
)
from lakehouse.utils.table_loader import load_table_templates


@pytest.fixture(autouse=True)
def _clear_cache():
    """Clear lru_cache between tests."""
    load_table_templates.cache_clear()
    yield
    load_table_templates.cache_clear()


def _write_template(tmpdir: Path, name: str, template: dict):
    """Write a YAML template to a temp directory."""
    path = tmpdir / f"{name}.yaml"
    path.write_text(yaml.dump(template))


def _base_template(**overrides):
    """Return a minimal valid template with optional overrides."""
    t = {
        "name": "test_table",
        "namespace": "lakehouse",
        "description": "Test table",
        "columns": [
            {"name": "id", "type": "string"},
            {"name": "value", "type": "double"},
        ],
        "partition_spec": [{"column": "id", "transform": "identity"}],
        "properties": {"write_format": "parquet"},
    }
    t.update(overrides)
    return t


class TestBuildSourceAssets:
    """Tests for the build_source_assets factory function."""

    def test_no_source_templates_returns_empty(self):
        """Factory returns [] when no templates have source blocks."""
        with tempfile.TemporaryDirectory() as tmpdir:
            _write_template(Path(tmpdir), "plain", _base_template())
            with patch(
                "lakehouse.assets.source_assets.load_table_templates",
                return_value=load_table_templates(Path(tmpdir)),
            ):
                assets = build_source_assets()
                assert assets == []

    def test_generates_asset_for_source_template(self):
        """Factory generates one asset per template with source."""
        with tempfile.TemporaryDirectory() as tmpdir:
            t = _base_template(
                source={"path": "s3://bucket/data/", "format": "parquet"}
            )
            _write_template(Path(tmpdir), "with_source", t)
            with patch(
                "lakehouse.assets.source_assets.load_table_templates",
                return_value=load_table_templates(Path(tmpdir)),
            ):
                assets = build_source_assets()
                assert len(assets) == 1

    def test_skips_templates_without_source(self):
        """Factory skips templates that have no source block."""
        with tempfile.TemporaryDirectory() as tmpdir:
            _write_template(Path(tmpdir), "no_source", _base_template())
            t = _base_template(
                name="sourced",
                source={"path": "s3://bucket/data/", "format": "parquet"},
            )
            _write_template(Path(tmpdir), "sourced", t)
            with patch(
                "lakehouse.assets.source_assets.load_table_templates",
                return_value=load_table_templates(Path(tmpdir)),
            ):
                assets = build_source_assets()
                assert len(assets) == 1

    def test_current_templates_produce_zero_source_assets(self):
        """The shipped templates (no uncommented source) produce 0 assets."""
        from lakehouse.assets.source_assets import source_ingestion_assets

        assert source_ingestion_assets == []


class TestReadSource:
    """Tests for the _read_source dispatch function."""

    def _schema(self):
        return pa.schema(
            [pa.field("id", pa.string()), pa.field("value", pa.float64())]
        )

    @patch("lakehouse.assets.source_assets.pad.dataset")
    def test_parquet_dispatch(self, mock_dataset):
        """Parquet format calls pad.dataset with format='parquet'."""
        mock_ds = MagicMock()
        mock_ds.to_table.return_value = pa.table(
            {"id": ["a"], "value": [1.0]}, schema=self._schema()
        )
        mock_dataset.return_value = mock_ds

        result = _read_source(
            {"path": "s3://bucket/data/", "format": "parquet"},
            self._schema(),
        )
        mock_dataset.assert_called_once_with(
            "s3://bucket/data/", format="parquet", schema=self._schema()
        )
        assert result.num_rows == 1

    @patch("lakehouse.assets.source_assets.pad.dataset")
    def test_csv_dispatch(self, mock_dataset):
        """CSV format calls pad.dataset with CsvFileFormat."""
        mock_ds = MagicMock()
        mock_ds.to_table.return_value = pa.table(
            {"id": ["a"], "value": [1.0]}, schema=self._schema()
        )
        mock_dataset.return_value = mock_ds

        result = _read_source(
            {"path": "s3://bucket/data/", "format": "csv"},
            self._schema(),
        )
        assert mock_dataset.called
        assert result.num_rows == 1

    @patch("lakehouse.assets.source_assets.pad.dataset")
    def test_json_dispatch(self, mock_dataset):
        """JSON format calls pad.dataset with format='json'."""
        mock_ds = MagicMock()
        mock_ds.to_table.return_value = pa.table(
            {"id": ["a"], "value": [1.0]}, schema=self._schema()
        )
        mock_dataset.return_value = mock_ds

        result = _read_source(
            {"path": "s3://bucket/data/", "format": "json"},
            self._schema(),
        )
        mock_dataset.assert_called_once_with("s3://bucket/data/", format="json")
        assert result.num_rows == 1

    def test_unsupported_format_raises(self):
        """Unsupported format raises ValueError."""
        with pytest.raises(ValueError, match="Unsupported source format"):
            _read_source(
                {"path": "s3://bucket/data/", "format": "avro"},
                self._schema(),
            )

    @patch("lakehouse.assets.source_assets.pad.dataset")
    def test_default_format_is_parquet(self, mock_dataset):
        """When format is omitted, defaults to parquet."""
        mock_ds = MagicMock()
        mock_ds.to_table.return_value = pa.table(
            {"id": ["a"], "value": [1.0]}, schema=self._schema()
        )
        mock_dataset.return_value = mock_ds

        _read_source({"path": "s3://bucket/data/"}, self._schema())
        mock_dataset.assert_called_once_with(
            "s3://bucket/data/", format="parquet", schema=self._schema()
        )
