"""Structured audit logging for compliance (SOC2 / HIPAA).

Emits JSON-structured events to a dedicated ``lakehouse.audit`` logger.
Events are automatically captured by CloudWatch (ECS) or Cloud Logging (GCP)
without additional infrastructure.
"""

import json
import logging
from datetime import datetime, timezone
from typing import Any

_audit_logger = logging.getLogger("lakehouse.audit")


def log_audit_event(event: str, table: str, *, details: dict[str, Any] | None = None) -> dict:
    """Emit a structured audit event.

    Args:
        event: Event type — one of ``table_read``, ``table_write``,
            ``source_ingest``, ``pii_columns_dropped``, ``schema_drift``.
        table: Fully qualified table name (e.g. ``lakehouse.event_stream``).
        details: Optional dict with event-specific data (row_count,
            columns_dropped, source_path, drift_details, etc.).

    Returns:
        The audit record dict (useful for testing).
    """
    record = {
        "timestamp": datetime.now(timezone.utc).isoformat(),
        "event": event,
        "table": table,
        "details": details or {},
    }
    _audit_logger.info(json.dumps(record, default=str))
    return record
