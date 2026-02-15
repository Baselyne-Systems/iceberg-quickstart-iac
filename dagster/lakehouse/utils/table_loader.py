"""Loads YAML table templates — single source of truth shared with Terraform."""

from pathlib import Path

import yaml

TABLE_TEMPLATES_DIR = Path(__file__).resolve().parents[3] / "table-templates"


def load_table_templates(templates_dir: Path | None = None) -> dict:
    """Load all YAML table templates into a dict keyed by template name."""
    templates_dir = templates_dir or TABLE_TEMPLATES_DIR
    templates = {}

    for yaml_path in sorted(templates_dir.glob("*.yaml")):
        with open(yaml_path) as f:
            template = yaml.safe_load(f)
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


def get_restricted_columns(template: dict) -> list[str]:
    """Extract column names marked as restricted."""
    return [
        col["name"]
        for col in template["columns"]
        if col.get("access_level") == "restricted"
    ]
