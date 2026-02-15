"""Loads YAML table templates — single source of truth shared with Terraform."""

import functools
from pathlib import Path

import pyarrow as pa
import yaml

TABLE_TEMPLATES_DIR = Path(__file__).resolve().parents[3] / "table-templates"

_REQUIRED_KEYS = {"name", "columns", "partition_spec"}


@functools.lru_cache(maxsize=1)
def load_table_templates(templates_dir: Path | None = None) -> dict:
    """Load all YAML table templates into a dict keyed by template name."""
    templates_dir = templates_dir or TABLE_TEMPLATES_DIR
    templates = {}

    for yaml_path in sorted(templates_dir.glob("*.yaml")):
        with open(yaml_path) as f:
            template = yaml.safe_load(f)

        if template is None:
            raise ValueError(f"Empty YAML file: {yaml_path}")

        missing = _REQUIRED_KEYS - set(template.keys())
        if missing:
            raise ValueError(
                f"Table template '{yaml_path.name}' missing required keys: {missing}. "
                f"Required: {_REQUIRED_KEYS}"
            )

        templates[yaml_path.stem] = template

    return templates


def get_template(name: str, templates_dir: Path | None = None) -> dict:
    """Load a single table template by name."""
    templates = load_table_templates(templates_dir)
    if name not in templates:
        raise KeyError(f"Table template '{name}' not found. Available: {list(templates.keys())}")
    return templates[name]


def get_column_names(template: dict) -> list[str]:
    """Extract column names from a table template."""
    return [col["name"] for col in template["columns"]]


def iceberg_type_to_arrow(iceberg_type: str) -> pa.DataType:
    """Map Iceberg type strings to PyArrow types."""
    mapping = {
        "boolean": pa.bool_(),
        "int": pa.int32(),
        "long": pa.int64(),
        "float": pa.float32(),
        "double": pa.float64(),
        "date": pa.date32(),
        "time": pa.time64("us"),
        "timestamp": pa.timestamp("us"),
        "timestamptz": pa.timestamp("us", tz="UTC"),
        "string": pa.string(),
        "uuid": pa.string(),
        "binary": pa.binary(),
    }
    return mapping.get(iceberg_type, pa.string())


def get_restricted_columns(template: dict) -> list[str]:
    """Extract column names marked as restricted."""
    return [
        col["name"]
        for col in template["columns"]
        if col.get("access_level") == "restricted"
    ]
