# SOC2 & HIPAA Compliance Guide

This document maps the controls in this Iceberg lakehouse template to SOC2 Trust Service Criteria and HIPAA Security Rule requirements.

---

## Overview

**SOC2** (Service Organization Control 2) defines controls for managing customer data based on five Trust Service Criteria: Security, Availability, Processing Integrity, Confidentiality, and Privacy.

**HIPAA** (Health Insurance Portability and Accountability Act) Security Rule (45 CFR Part 164) requires administrative, physical, and technical safeguards for electronic Protected Health Information (ePHI).

This template provides infrastructure-level controls. Your organization must also implement administrative controls (policies, training, incident response procedures) that are outside the scope of IaC.

---

## Compliance Control Matrix

### SOC2 Trust Service Criteria

| SOC2 Criteria | Control | Implementation | Files |
|---|---|---|---|
| **CC6.1** — Logical access security | Three-tier IAM roles (reader/writer/admin) | Column-level access via Lake Formation (AWS) and Data Catalog policy tags (GCP) | `aws/modules/iam/`, `gcp/modules/iam/` |
| **CC6.1** — Logical access security | PII column masking in Dagster | Reader access level drops restricted columns at query time | `dagster/lakehouse/resources/iceberg.py` |
| **CC6.6** — Encryption in transit | TLS enforcement on S3 bucket | Bucket policy denies non-HTTPS requests | `aws/modules/storage/main.tf` |
| **CC6.6** — Encryption in transit | TLS 1.3 on ALB | HTTPS listener uses `ELBSecurityPolicy-TLS13-1-2-2021-06` | `aws/modules/catalog_nessie/main.tf` |
| **CC6.7** — Encryption at rest | KMS encryption on S3 | Server-side encryption with `aws:kms`, bucket key enabled | `aws/modules/storage/main.tf` |
| **CC6.7** — Encryption at rest | CMEK encryption on GCS | Customer-managed KMS key with 90-day rotation | `gcp/modules/storage/main.tf` |
| **CC7.2** — Monitoring & detection | CloudTrail S3 data events | All S3 reads/writes to the lakehouse bucket are logged | `aws/modules/storage/cloudtrail.tf` |
| **CC7.2** — Monitoring & detection | GCP audit log sink | Data access logs exported to dedicated audit bucket | `gcp/modules/storage/audit_logging.tf` |
| **CC7.2** — Monitoring & detection | Schema drift sensor | Hourly comparison of live schema against YAML definitions | `dagster/lakehouse/sensors/schema_drift.py` |
| **CC7.2** — Monitoring & detection | Dagster structured audit logging | JSON audit events for all table reads, writes, and PII operations | `dagster/lakehouse/utils/audit.py` |
| **CC7.2** — Monitoring & detection | CloudWatch alarms | CPU/memory alerts with SNS integration | `aws/modules/catalog_nessie/` |
| **CC8.1** — Change management | Infrastructure as Code | All infrastructure defined in Terraform with version control | `aws/`, `gcp/` |
| **CC8.1** — Change management | YAML-driven table definitions | Single source of truth prevents schema drift | `table-templates/*.yaml` |

### HIPAA Security Rule (45 CFR 164.312)

| HIPAA Section | Requirement | Implementation | Files |
|---|---|---|---|
| **§164.312(a)(1)** — Access control | Unique user identification | Three-tier IAM roles with distinct permissions | `aws/modules/iam/`, `gcp/modules/iam/` |
| **§164.312(a)(1)** — Access control | Automatic logoff | Session management delegated to AWS/GCP IAM | N/A (cloud provider) |
| **§164.312(b)** — Audit controls | Record and examine activity | CloudTrail data events (AWS), audit log sink (GCP), Dagster audit logs | `aws/modules/storage/cloudtrail.tf`, `gcp/modules/storage/audit_logging.tf`, `dagster/lakehouse/utils/audit.py` |
| **§164.312(c)(1)** — Integrity | Protect ePHI from alteration | S3 versioning, bucket key encryption, CMEK on GCS | `aws/modules/storage/main.tf`, `gcp/modules/storage/main.tf` |
| **§164.312(d)** — Authentication | Verify identity | IAM authentication (AWS SigV4, GCP OAuth 2.0) | Cloud provider |
| **§164.312(e)(1)** — Transmission security | Encrypt ePHI in transit | TLS bucket policies, ALB TLS 1.3, HTTPS enforcement | `aws/modules/storage/main.tf`, `aws/modules/catalog_nessie/main.tf` |
| **§164.316(b)(2)(i)** — Retention | Retain documentation 6 years | Audit logs: 7-year lifecycle; CloudWatch: configurable (default 365 days) | `aws/modules/storage/cloudtrail.tf`, `gcp/modules/storage/audit_logging.tf` |

---

## Encryption

### At Rest

**AWS:**
- S3 bucket uses SSE-KMS with bucket key enabled (`aws/modules/storage/main.tf`)
- Audit trail bucket uses SSE-KMS (`aws/modules/storage/cloudtrail.tf`)
- DynamoDB (Nessie) uses AWS-managed encryption with point-in-time recovery

**GCP:**
- GCS bucket uses CMEK with a 90-day key rotation when `enable_cmek = true` (`gcp/modules/storage/main.tf`)
- KMS key ring and crypto key are protected with `prevent_destroy` lifecycle rules

### In Transit

- S3 bucket policy denies any request where `aws:SecureTransport = false`
- ALB HTTPS listener uses TLS 1.3 policy (`ELBSecurityPolicy-TLS13-1-2-2021-06`)
- HTTP requests to ALB are redirected to HTTPS (301) when a certificate is configured

---

## Access Control

### Three-Tier IAM Roles

| Role | S3/GCS | Catalog | PII Columns |
|------|--------|---------|-------------|
| **Reader** | Read-only | SELECT on public columns | Masked/dropped |
| **Writer** | Read/write | SELECT + INSERT + DELETE | Full access |
| **Admin** | Full | All operations | Full access |

### Dagster PII Masking

When `LAKEHOUSE_ACCESS_LEVEL=reader`, the IO manager (`resources/iceberg.py`) drops columns marked `access_level: restricted` in the YAML template before returning data. This ensures PII is never exposed to reader-level workloads. All PII masking events are recorded in the audit log.

---

## Audit Trail

### AWS CloudTrail

When `enable_cloudtrail = true` (default), a CloudTrail trail captures all S3 data events (GetObject, PutObject, DeleteObject) on the lakehouse bucket. Logs are stored in a dedicated audit bucket with:
- SSE-KMS encryption
- Versioning enabled
- 7-year lifecycle (90 days Standard → Standard-IA → Glacier → expiration)
- Public access blocked
- Log file validation enabled

### GCP Audit Log Sink

When `enable_audit_logging = true` (default), a logging sink exports data access logs for the lakehouse GCS bucket to a dedicated audit bucket with a 7-year lifecycle.

### Dagster Structured Audit Logging

The `lakehouse.audit` Python logger emits JSON-structured events for:

| Event | When | Details |
|-------|------|---------|
| `table_write` | Data written to Iceberg table | row_count, columns |
| `table_read` | Data read from Iceberg table | row_count, access_level |
| `source_ingest` | Source files ingested | source_path, format, row_count |
| `pii_columns_dropped` | PII columns masked for reader access | columns_dropped, access_level |
| `schema_drift` | Live schema doesn't match YAML template | missing_columns, extra_columns, type_mismatches |

These logs are automatically captured by CloudWatch (ECS) or Cloud Logging (GCP) and included in the audit trail.

---

## Data Retention & Lifecycle

| Resource | Retention | Policy |
|----------|-----------|--------|
| Lakehouse data (S3) | Indefinite (versioned) | 90d → Standard-IA, old versions expire after 30d |
| Lakehouse data (GCS) | Indefinite (versioned) | 90d → Nearline, archived versions expire after 30d |
| CloudTrail audit logs | 7 years | 90d → Standard-IA → 1y → Glacier → 7y expiration |
| GCP audit logs | 7 years | 1y → Coldline → 7y expiration |
| CloudWatch logs (Nessie) | Configurable (`log_retention_days`, default 365) | Auto-expired by CloudWatch |

---

## Network Security

When using Nessie (`catalog_type = "nessie"`):

- **VPC isolation**: Nessie runs in a dedicated VPC with public and private subnets
- **Private subnets**: ECS tasks run in private subnets with no direct internet access
- **Security groups**: ALB accepts traffic only from `nessie_allowed_cidrs`; ECS tasks accept traffic only from the ALB security group
- **Internal ALB**: Default `nessie_internal = true` prevents internet-facing exposure
- **No public IPs**: Fargate tasks have `assign_public_ip = false`

---

## Container Security

The Dagster Docker deployment includes:

- **Pinned base image**: `python:3.11.11-slim` — prevents supply chain drift from `latest`
- **Non-root user**: `dagster` user created in Dockerfile, all processes run as non-root
- **Capability drops**: `cap_drop: [ALL]` removes all Linux capabilities
- **No privilege escalation**: `security_opt: ["no-new-privileges:true"]`
- **Read-only filesystem**: `read_only: true` with `tmpfs: ["/tmp"]` for writable temp
- **Resource limits**: CPU and memory limits in `docker-compose.yaml`

---

## Monitoring & Incident Response

### CloudWatch Alarms (AWS)

When `alarm_sns_topic_arn` is set, alarms notify on:
- ECS service CPU > 70% (auto-scaling trigger)
- Nessie health check failures

### Schema Drift Alerts

The schema drift sensor runs hourly and sends alerts via:
- **SNS**: Set `ALERT_SNS_TOPIC_ARN` in Dagster environment
- **Slack**: Set `ALERT_SLACK_WEBHOOK_URL` in Dagster environment

### Dagster Audit Log Monitoring

Audit events from the `lakehouse.audit` logger can be used to set up CloudWatch Metric Filters or GCP log-based metrics for:
- Unusual read patterns (high `table_read` frequency)
- PII access events (`pii_columns_dropped`)
- Schema drift occurrences

---

## Production Hardening Checklist

Use this checklist when preparing for a SOC2 audit or HIPAA compliance review:

- [ ] **Encryption at rest**: Verify `enable_cmek = true` (GCP) and S3 SSE-KMS is active
- [ ] **Encryption in transit**: Set `certificate_arn` for HTTPS on Nessie ALB
- [ ] **Audit logging**: Verify `enable_cloudtrail = true` (AWS) and `enable_audit_logging = true` (GCP)
- [ ] **Log retention**: Set `log_retention_days >= 365` for SOC2 (>= 2190 for HIPAA)
- [ ] **Access control**: Configure `lake_formation_admins` with specific IAM principals
- [ ] **Network isolation**: Set `nessie_internal = true` and restrict `nessie_allowed_cidrs`
- [ ] **Container hardening**: Use the provided `docker-compose.yaml` with security options
- [ ] **Alerting**: Configure `alarm_sns_topic_arn` and/or `ALERT_SLACK_WEBHOOK_URL`
- [ ] **Data quality**: Review and customize Soda checks in `quality/soda_checks/`
- [ ] **PII governance**: Mark all sensitive columns with `access_level: restricted` in YAML templates
- [ ] **Terraform state**: Enable remote backend with encryption and access logging
- [ ] **Backup & recovery**: Verify S3/GCS versioning is enabled and test restore procedures
- [ ] **Incident response**: Document and test your incident response runbook
- [ ] **Access reviews**: Schedule quarterly IAM permission audits
