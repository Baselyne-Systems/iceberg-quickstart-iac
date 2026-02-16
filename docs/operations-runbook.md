# Operations Runbook

Procedures for incident response, disaster recovery, credential rotation, and common failure scenarios.

---

## Incident Response

### Containment

1. **Identify the blast radius** — which environment (dev/prod), which service (Nessie, Dagster, S3)?
2. **Isolate the affected component**:
   - Nessie: Scale ECS service to 0 tasks — `aws ecs update-service --cluster <cluster> --service <service> --desired-count 0`
   - S3: Add a deny-all bucket policy temporarily
   - Dagster: Stop the ECS service or `docker compose down`
3. **Preserve evidence** — do NOT delete logs, containers, or state files

### Evidence Preservation

```bash
# Export CloudTrail events for the incident window
aws cloudtrail lookup-events \
  --start-time "2024-01-15T00:00:00Z" \
  --end-time "2024-01-15T23:59:59Z" \
  --output json > incident-cloudtrail.json

# Export CloudWatch logs
aws logs filter-log-events \
  --log-group-name /ecs/nessie \
  --start-time 1705276800000 \
  --end-time 1705363200000 > incident-ecs-logs.json

# Snapshot the Terraform state
aws s3 cp s3://my-tf-state/iceberg-lakehouse/prod/terraform.tfstate \
  incident-tfstate-backup.json
```

### Communication

1. Notify the on-call engineer (PagerDuty / Slack `#incidents`)
2. Create an incident channel: `#inc-YYYY-MM-DD-short-description`
3. Post a status update every 30 minutes until resolved
4. Notify affected stakeholders once contained

### Post-Mortem Template

```markdown
## Incident: [Title]
**Date**: YYYY-MM-DD
**Duration**: HH:MM
**Severity**: P1/P2/P3
**On-call**: [Name]

### Timeline
- HH:MM — [Event]

### Root Cause
[Description]

### Impact
- Users affected: [count/scope]
- Data affected: [tables/rows]

### Resolution
[What fixed it]

### Action Items
- [ ] [Preventive measure] — Owner: [Name] — Due: [Date]
```

---

## Disaster Recovery

### RTO/RPO Targets

| Component | RPO (data loss tolerance) | RTO (recovery time) | Strategy |
|-----------|--------------------------|--------------------|-----------|
| S3 lakehouse data | 0 (versioned) | < 1 hour | S3 versioning + cross-region replication (if enabled) |
| Terraform state | 0 (versioned) | < 30 min | S3 versioning on state bucket |
| Nessie catalog (DynamoDB) | < 1 second | < 1 hour | Point-in-time recovery (PITR) |
| Dagster pipelines | 0 (in Git) | < 15 min | Redeploy from Git |
| CloudTrail audit logs | 0 (versioned) | < 1 hour | Separate audit bucket with versioning |

### Terraform State Recovery

```bash
# List available versions of the state file
aws s3api list-object-versions \
  --bucket my-tf-state \
  --prefix iceberg-lakehouse/prod/terraform.tfstate

# Restore a previous version
aws s3api get-object \
  --bucket my-tf-state \
  --key iceberg-lakehouse/prod/terraform.tfstate \
  --version-id <version-id> \
  restored-state.tfstate

# Replace the current state (CAUTION)
aws s3 cp restored-state.tfstate \
  s3://my-tf-state/iceberg-lakehouse/prod/terraform.tfstate
```

### Nessie DynamoDB Recovery (Point-in-Time)

```bash
# Restore to a specific point in time
aws dynamodb restore-table-to-point-in-time \
  --source-table-name myproject-prod-nessie \
  --target-table-name myproject-prod-nessie-restored \
  --restore-date-time "2024-01-15T12:00:00Z"

# After verification, swap the table (update Terraform config and apply)
```

### S3 Data Recovery

```bash
# List deleted objects
aws s3api list-object-versions \
  --bucket myproject-prod-lakehouse \
  --prefix data/ \
  --query 'DeleteMarkers[?IsLatest==`true`]'

# Restore a deleted object (remove the delete marker)
aws s3api delete-object \
  --bucket myproject-prod-lakehouse \
  --key data/event_stream/file.parquet \
  --version-id <delete-marker-version-id>

# Restore a previous version
aws s3api copy-object \
  --bucket myproject-prod-lakehouse \
  --copy-source myproject-prod-lakehouse/data/event_stream/file.parquet?versionId=<old-version> \
  --key data/event_stream/file.parquet
```

---

## Break-Glass Access

Emergency access when normal IAM roles are compromised or unavailable.

### Prerequisites

- A break-glass IAM user with `AdministratorAccess`, MFA-protected, console password disabled
- Credentials stored in a physical safe or hardware security module
- Access logged and reviewed after every use

### Procedure

1. Two authorized personnel retrieve the break-glass credentials
2. Log into the AWS console with the break-glass user + MFA
3. Perform the minimum necessary actions to restore normal access
4. Document every action taken in the incident channel
5. Rotate the break-glass credentials after use
6. File a post-mortem explaining why break-glass was needed

---

## Credential Rotation

### IAM Access Keys

```bash
# Create a new key
aws iam create-access-key --user-name <user>

# Update all systems using the old key, then:
aws iam delete-access-key --user-name <user> --access-key-id <old-key-id>
```

Prefer IAM roles over access keys. If keys are required, rotate every 90 days.

### ACM Certificates (Nessie ALB)

ACM certificates auto-renew if validated via DNS. Verify renewal status:

```bash
aws acm describe-certificate --certificate-arn <arn> \
  --query 'Certificate.{Status:Status,NotAfter:NotAfter,RenewalSummary:RenewalSummary}'
```

If renewal fails, re-validate the domain or issue a new certificate and update the `certificate_arn` in your tfvars.

### SNS Subscription Confirmation

SNS email subscriptions expire if not confirmed. Re-subscribe:

```bash
aws sns subscribe \
  --topic-arn <topic-arn> \
  --protocol email \
  --notification-endpoint alerts@company.com
```

---

## Common Failure Runbooks

### Nessie Unreachable

**Symptoms**: Dagster jobs fail with connection errors to the Nessie endpoint.

1. Check ECS service status:
   ```bash
   aws ecs describe-services --cluster <cluster> --services <service> \
     --query 'services[0].{desired:desiredCount,running:runningCount,events:events[:3]}'
   ```
2. Check target group health:
   ```bash
   aws elbv2 describe-target-health --target-group-arn <tg-arn>
   ```
3. Check Nessie container logs:
   ```bash
   aws logs tail /ecs/nessie --since 30m
   ```
4. Common causes:
   - **OOM**: Increase `nessie_memory` in tfvars and redeploy
   - **DynamoDB throttling**: Check `ThrottledRequests` metric, switch to on-demand billing
   - **Security group**: Verify ALB SG allows inbound from the Dagster network

### Dagster OOM (Out of Memory)

**Symptoms**: ECS task or Docker container killed, exit code 137.

1. Check CloudWatch metrics for the ECS service memory utilization
2. Increase memory in the ECS task definition or `docker-compose.yaml`
3. For large datasets, use chunked processing in the Dagster asset:
   ```python
   for batch in pd.read_parquet(path, chunksize=100_000):
       # process batch
   ```

### Schema Drift Alert

**Symptoms**: The `schema_drift_sensor` fires an alert.

1. Check the alert details — which table, what drifted (missing columns, type changes, extra columns)
2. Determine if the drift is intentional:
   - **Intentional**: Update the table template YAML to match, then `terraform apply`
   - **Unintentional**: Investigate which process modified the schema. Check CloudTrail for `UpdateTable` / `UpdateSchema` calls
3. After resolution, the next sensor tick should clear the alert

### S3 403 Forbidden

**Symptoms**: Dagster or Athena returns `AccessDenied` on S3 operations.

1. Verify the IAM role has the correct S3 permissions:
   ```bash
   aws iam simulate-principal-policy \
     --policy-source-arn <role-arn> \
     --action-names s3:GetObject s3:PutObject \
     --resource-arns arn:aws:s3:::myproject-prod-lakehouse/*
   ```
2. Check the S3 bucket policy for explicit denies
3. If using Lake Formation, verify the principal has the required data permissions
4. Check for VPC endpoint policies if accessing from a private subnet

---

## Monitoring Escalation

### CloudWatch Alarms

| Alarm | Meaning | Action |
|-------|---------|--------|
| `nessie-cpu-high` | ECS CPU > 70% sustained | Check for runaway queries. If legitimate load, increase `nessie_cpu` or add auto-scaling. |
| `nessie-health-check-failed` | ALB health checks failing | See "Nessie Unreachable" above. |
| `dagster-task-stopped` | ECS task exited unexpectedly | Check exit code. 137 = OOM, 1 = application error. Check logs. |

### Escalation Path

1. **L1 — On-call engineer**: Acknowledge alert within 15 minutes. Attempt resolution using this runbook.
2. **L2 — Platform team lead**: Escalate if not resolved within 1 hour or if data loss is suspected.
3. **L3 — Engineering director + security**: Escalate for security incidents, data breaches, or extended outages (> 4 hours).
