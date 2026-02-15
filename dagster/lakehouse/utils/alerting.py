"""Alerting helpers for SNS and Slack webhooks."""

import json
import logging
import os
from urllib.request import Request, urlopen

logger = logging.getLogger(__name__)


def send_sns_alert(topic_arn: str, subject: str, message: str) -> None:
    """Send an alert via AWS SNS."""
    import boto3

    client = boto3.client("sns")
    client.publish(
        TopicArn=topic_arn,
        Subject=subject[:100],
        Message=message,
    )
    logger.info("SNS alert sent to %s: %s", topic_arn, subject)


def send_slack_alert(webhook_url: str, message: str) -> None:
    """Send an alert via Slack webhook."""
    payload = json.dumps({"text": message}).encode("utf-8")
    req = Request(
        webhook_url,
        data=payload,
        headers={"Content-Type": "application/json"},
    )
    urlopen(req)  # noqa: S310
    logger.info("Slack alert sent")


def alert(subject: str, message: str) -> None:
    """Send alert via configured channel (SNS or Slack)."""
    sns_topic = os.environ.get("ALERT_SNS_TOPIC_ARN")
    slack_url = os.environ.get("ALERT_SLACK_WEBHOOK_URL")

    if sns_topic:
        send_sns_alert(sns_topic, subject, message)
    if slack_url:
        send_slack_alert(slack_url, f"*{subject}*\n{message}")
    if not sns_topic and not slack_url:
        logger.warning("No alerting channel configured. Subject: %s Message: %s", subject, message)
