"""Tests for structured audit logging."""

import json
import logging

from lakehouse.utils.audit import log_audit_event


class TestLogAuditEvent:
    """Tests for the log_audit_event function."""

    def test_emits_valid_json(self, caplog):
        """Audit events are valid JSON with required fields."""
        with caplog.at_level(logging.INFO, logger="lakehouse.audit"):
            record = log_audit_event("table_write", "lakehouse.events", details={"row_count": 42})

        assert record["event"] == "table_write"
        assert record["table"] == "lakehouse.events"
        assert record["details"]["row_count"] == 42
        assert "timestamp" in record

        # The logged message should be valid JSON
        log_msg = caplog.records[-1].message
        parsed = json.loads(log_msg)
        assert parsed["event"] == "table_write"

    def test_table_read_event(self, caplog):
        """table_read events include correct structure."""
        with caplog.at_level(logging.INFO, logger="lakehouse.audit"):
            record = log_audit_event(
                "table_read",
                "lakehouse.users",
                details={
                    "row_count": 100,
                    "access_level": "reader",
                },
            )

        assert record["event"] == "table_read"
        assert record["details"]["access_level"] == "reader"

    def test_source_ingest_event(self):
        """source_ingest events include source_path."""
        record = log_audit_event(
            "source_ingest",
            "lakehouse.raw_events",
            details={
                "source_path": "s3://bucket/data/",
                "format": "parquet",
                "row_count": 1000,
            },
        )

        assert record["event"] == "source_ingest"
        assert record["details"]["source_path"] == "s3://bucket/data/"

    def test_pii_columns_dropped_event(self):
        """pii_columns_dropped events list the dropped columns."""
        record = log_audit_event(
            "pii_columns_dropped",
            "lakehouse.events",
            details={
                "columns_dropped": ["email", "ip_address"],
                "access_level": "reader",
            },
        )

        assert record["event"] == "pii_columns_dropped"
        assert record["details"]["columns_dropped"] == ["email", "ip_address"]

    def test_schema_drift_event(self):
        """schema_drift events include drift details."""
        record = log_audit_event(
            "schema_drift",
            "lakehouse.events",
            details={
                "missing_columns": ["session_id"],
                "extra_columns": ["debug_flag"],
                "type_mismatches": {},
            },
        )

        assert record["event"] == "schema_drift"
        assert record["details"]["missing_columns"] == ["session_id"]

    def test_empty_details_defaults_to_dict(self):
        """When details is omitted, an empty dict is used."""
        record = log_audit_event("table_read", "lakehouse.events")
        assert record["details"] == {}

    def test_timestamp_is_utc_iso(self):
        """Timestamp is in UTC ISO 8601 format."""
        record = log_audit_event("table_read", "lakehouse.events")
        assert record["timestamp"].endswith("+00:00")
