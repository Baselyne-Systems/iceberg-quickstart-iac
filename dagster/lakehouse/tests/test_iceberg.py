"""Tests for Iceberg IO manager config."""

import os

import pytest


def test_get_catalog_config_aws_glue(monkeypatch):
    """aws-glue backend returns glue config."""
    monkeypatch.setenv("LAKEHOUSE_BACKEND", "aws-glue")
    monkeypatch.setenv("AWS_REGION", "us-west-2")

    from lakehouse.resources.iceberg import _get_catalog_config

    config = _get_catalog_config()
    assert config["type"] == "glue"
    assert config["s3.region"] == "us-west-2"


def test_get_catalog_config_aws_nessie(monkeypatch):
    """aws-nessie backend returns rest config with NESSIE_URI."""
    monkeypatch.setenv("LAKEHOUSE_BACKEND", "aws-nessie")
    monkeypatch.setenv("NESSIE_URI", "http://nessie:19120/api/v2")
    monkeypatch.setenv("AWS_REGION", "us-east-1")

    from lakehouse.resources.iceberg import _get_catalog_config

    config = _get_catalog_config()
    assert config["type"] == "rest"
    assert config["uri"] == "http://nessie:19120/api/v2"


def test_get_catalog_config_gcp(monkeypatch):
    """gcp backend returns rest config."""
    monkeypatch.setenv("LAKEHOUSE_BACKEND", "gcp")
    monkeypatch.setenv("ICEBERG_REST_URI", "http://rest:8181")
    monkeypatch.setenv("GCP_PROJECT_ID", "my-project")

    from lakehouse.resources.iceberg import _get_catalog_config

    config = _get_catalog_config()
    assert config["type"] == "rest"
    assert config["gcs.project-id"] == "my-project"


def test_get_catalog_config_invalid_backend(monkeypatch):
    """Invalid LAKEHOUSE_BACKEND raises ValueError."""
    monkeypatch.setenv("LAKEHOUSE_BACKEND", "invalid-backend")

    from lakehouse.resources.iceberg import _get_catalog_config

    with pytest.raises(ValueError, match="Unknown LAKEHOUSE_BACKEND"):
        _get_catalog_config()


def test_get_catalog_config_nessie_missing_uri(monkeypatch):
    """aws-nessie without NESSIE_URI raises KeyError."""
    monkeypatch.setenv("LAKEHOUSE_BACKEND", "aws-nessie")
    monkeypatch.delenv("NESSIE_URI", raising=False)

    from lakehouse.resources.iceberg import _get_catalog_config

    with pytest.raises(KeyError):
        _get_catalog_config()


def test_get_catalog_config_default(monkeypatch):
    """Default backend is aws-glue."""
    monkeypatch.delenv("LAKEHOUSE_BACKEND", raising=False)

    from lakehouse.resources.iceberg import _get_catalog_config

    config = _get_catalog_config()
    assert config["type"] == "glue"
