"""Tests for alerting utilities."""

import logging
from unittest.mock import MagicMock, patch

from lakehouse.utils.alerting import alert, send_slack_alert, send_sns_alert


def test_alert_no_channels(monkeypatch, caplog):
    """No channels configured logs warning but doesn't crash."""
    monkeypatch.delenv("ALERT_SNS_TOPIC_ARN", raising=False)
    monkeypatch.delenv("ALERT_SLACK_WEBHOOK_URL", raising=False)

    with caplog.at_level(logging.WARNING):
        alert("Test Subject", "Test message")

    assert "No alerting channel configured" in caplog.text


def test_sns_failure_does_not_crash(monkeypatch):
    """SNS failure is caught and logged, doesn't crash caller."""
    monkeypatch.setenv("ALERT_SNS_TOPIC_ARN", "arn:aws:sns:us-east-1:123:topic")
    monkeypatch.delenv("ALERT_SLACK_WEBHOOK_URL", raising=False)

    with patch("lakehouse.utils.alerting.send_sns_alert", side_effect=Exception("SNS down")):
        # Should not raise — alert() catches exceptions in send_sns_alert
        # But since alert() calls send_sns_alert directly, we need to test send_sns_alert
        pass

    # Test send_sns_alert directly catches its own exceptions
    with patch.dict("sys.modules", {"boto3": MagicMock(side_effect=Exception("boom"))}):
        # send_sns_alert wraps in try/except so this should not raise
        send_sns_alert("arn:aws:sns:us-east-1:123:topic", "Test", "msg")


def test_slack_timeout_does_not_crash():
    """Slack timeout is caught and logged, doesn't crash caller."""
    # send_slack_alert wraps in try/except
    with patch("lakehouse.utils.alerting.urlopen", side_effect=TimeoutError("timed out")):
        send_slack_alert("https://hooks.slack.com/test", "test message")


def test_alert_calls_sns_when_configured(monkeypatch):
    """Alert dispatches to SNS when configured."""
    monkeypatch.setenv("ALERT_SNS_TOPIC_ARN", "arn:aws:sns:us-east-1:123:topic")
    monkeypatch.delenv("ALERT_SLACK_WEBHOOK_URL", raising=False)

    with patch("lakehouse.utils.alerting.send_sns_alert") as mock_sns:
        alert("Subject", "Message")
        mock_sns.assert_called_once_with("arn:aws:sns:us-east-1:123:topic", "Subject", "Message")


def test_alert_calls_slack_when_configured(monkeypatch):
    """Alert dispatches to Slack when configured."""
    monkeypatch.delenv("ALERT_SNS_TOPIC_ARN", raising=False)
    monkeypatch.setenv("ALERT_SLACK_WEBHOOK_URL", "https://hooks.slack.com/test")

    with patch("lakehouse.utils.alerting.send_slack_alert") as mock_slack:
        alert("Subject", "Message")
        mock_slack.assert_called_once()
