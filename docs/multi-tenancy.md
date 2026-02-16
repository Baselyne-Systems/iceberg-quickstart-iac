# Multi-Tenancy Guide

How to isolate tenants at each layer of the lakehouse — from soft isolation (same org, different teams) to hard isolation (external customers who must never see each other's data).

---

## Choosing an Isolation Level

The right level depends on who your tenants are:

| Scenario | Isolation Level | What Fails Safely |
|----------|----------------|-------------------|
| Internal teams in the same org | Soft | A misconfigured IAM policy is an inconvenience, not a breach |
| Business units with different compliance requirements | Medium | Need separation of data and audit trails, but shared platform is OK |
| External customers / regulated multi-party data | Hard | Every software control could fail and tenants still can't see each other |

---

## Storage Layer

### Soft: Prefix Isolation

Single bucket, tenant data separated by S3/GCS key prefix.

```
s3://myproject-prod-lakehouse/
├── acme/lakehouse/event_stream/data/
├── acme/lakehouse/event_stream/metadata/
├── globex/lakehouse/event_stream/data/
└── globex/lakehouse/event_stream/metadata/
```

**IAM enforcement**: Scope policies to a tenant's prefix.

```json
{
  "Effect": "Allow",
  "Action": ["s3:GetObject", "s3:PutObject"],
  "Resource": "arn:aws:s3:::myproject-prod-lakehouse/acme/*"
}
```

**Pros**: Simple. One bucket to manage. Cross-tenant analytics possible for admins.

**Cons**: S3 bucket policies max out at 20KB — becomes a constraint beyond ~20 tenants. A single overly broad IAM policy (`Resource: *`) breaks all isolation. No separate encryption keys per tenant.

**GCP equivalent**: Same pattern with GCS prefixes and IAM conditions:

```json
{
  "condition": {
    "expression": "resource.name.startsWith('projects/_/buckets/lakehouse/objects/acme/')"
  }
}
```

### Medium: Separate Buckets

One bucket per tenant, created by Terraform.

```hcl
# In your tfvars or tenant config
tenants = ["acme", "globex"]

# Terraform creates:
# myproject-prod-acme-lakehouse
# myproject-prod-globex-lakehouse
```

**Pros**: Bucket policies are per-tenant (no prefix games). Separate KMS keys per tenant possible. Separate lifecycle policies per tenant. Clean blast radius.

**Cons**: More Terraform resources. Cross-tenant queries require Athena federation or a platform-level role with access to all buckets.

### Hard: Separate AWS Accounts

Each tenant gets its own AWS account (via AWS Organizations).

**Pros**: IAM boundary is the account itself. Even `AdministratorAccess` in tenant A's account can't touch tenant B. Separate billing. Separate CloudTrail. Maximum compliance story.

**Cons**: Operational complexity. Need AWS Organizations, cross-account roles for the platform team, centralized logging via a management account.

**When to use**: SaaS products handling customer data, healthcare platforms, financial services with regulatory separation requirements.

---

## Catalog Layer

### Glue: Database Per Tenant

```hcl
# One database per tenant
resource "aws_glue_catalog_database" "tenant" {
  for_each = toset(var.tenants)
  name     = "${var.project_name}_${var.environment}_${each.key}"
}

# Tables within each tenant's database
resource "aws_glue_catalog_table" "tenant_tables" {
  for_each      = { for pair in setproduct(var.tenants, keys(var.table_templates)) :
                     "${pair[0]}-${pair[1]}" => { tenant = pair[0], template = pair[1] } }
  database_name = "${var.project_name}_${var.environment}_${each.value.tenant}"
  name          = var.table_templates[each.value.template].name
  # ... columns from template
}
```

**Lake Formation**: Scope permissions per database.

```hcl
resource "aws_lakeformation_permissions" "tenant_reader" {
  for_each    = toset(var.tenants)
  principal   = aws_iam_role.tenant_reader[each.key].arn
  permissions = ["SELECT"]
  database {
    name = "${var.project_name}_${var.environment}_${each.key}"
  }
}
```

Tenant A's reader role can only query `myproject_prod_acme`, not `myproject_prod_globex`.

### Nessie: Namespace Per Tenant

Nessie namespaces map naturally to tenants:

```
Nessie catalog
├── acme.event_stream
├── acme.scd_type2
├── globex.event_stream
└── globex.scd_type2
```

PyIceberg accesses tenant-scoped tables:

```python
catalog = load_catalog("lakehouse", **config)
table = catalog.load_table(f"{tenant}.event_stream")
```

**Nessie branches per tenant**: Each tenant can have their own branch for experimentation without affecting others.

```
main branch: shared production state
├── acme/dev: Acme's experimental branch
└── globex/staging: Globex's staging branch
```

**Stronger isolation**: Run separate Nessie instances per tenant (separate ECS services, separate DynamoDB tables). Higher cost (~$65-80/month per tenant) but complete catalog isolation.

### BigLake: Dataset Per Tenant

```hcl
resource "google_bigquery_dataset" "tenant" {
  for_each   = toset(var.tenants)
  dataset_id = "${var.project_name}_${var.environment}_${each.key}"
  # ...
}
```

IAM bindings per dataset ensure tenant A's service account can only query `myproject_prod_acme`.

---

## IAM Layer

The current three-tier model (reader / writer / admin) becomes a matrix: one set of roles per tenant.

### Role Structure

```
# Current (single-tenant)
lakehouse-reader
lakehouse-writer
lakehouse-admin

# Multi-tenant
acme-reader,   acme-writer,   acme-admin
globex-reader, globex-writer, globex-admin
platform-admin   # Cross-tenant access for the platform team
```

### AWS Implementation

```hcl
resource "aws_iam_role" "tenant_reader" {
  for_each = toset(var.tenants)
  name     = "${var.project_name}-${var.environment}-${each.key}-reader"
  # ...
}

resource "aws_iam_role_policy" "tenant_reader_s3" {
  for_each = toset(var.tenants)
  role     = aws_iam_role.tenant_reader[each.key].id
  policy   = jsonencode({
    Statement = [{
      Effect   = "Allow"
      Action   = ["s3:GetObject"]
      Resource = "${aws_s3_bucket.tenant[each.key].arn}/*"
    }]
  })
}
```

### GCP Implementation

```hcl
resource "google_service_account" "tenant_reader" {
  for_each   = toset(var.tenants)
  account_id = "${var.project_name}-${each.key}-reader"
}

resource "google_storage_bucket_iam_member" "tenant_reader" {
  for_each = toset(var.tenants)
  bucket   = google_storage_bucket.tenant[each.key].name
  role     = "roles/storage.objectViewer"
  member   = "serviceAccount:${google_service_account.tenant_reader[each.key].email}"
}
```

### Column-Level Governance Per Tenant

The current system applies `access_level: restricted` uniformly — all tenants have the same PII rules. For tenant-specific PII policies, use an overlay pattern:

```yaml
# table-templates/event_stream.yaml (shared base)
columns:
  - name: phone
    type: string
    access_level: public     # Default: not restricted
```

```yaml
# tenants/acme.yaml (tenant-specific overrides)
tenant: acme
access_overrides:
  event_stream:
    phone: restricted        # Acme considers phone PII
```

The Dagster IO manager and Terraform IAM module would merge the base template with tenant overrides to determine which columns are restricted per tenant.

---

## Pipeline Layer (Dagster)

### Soft: Dagster Partitions

Single Dagster deployment. Each tenant is a partition key.

```python
from dagster import DynamicPartitionsDefinition, asset

tenants = DynamicPartitionsDefinition(name="tenant")

@asset(partitions_def=tenants)
def event_stream(context):
    tenant = context.partition_key  # "acme" or "globex"
    templates = load_table_templates()
    catalog = load_catalog("lakehouse", **_get_catalog_config())
    table = catalog.load_table(f"{tenant}.event_stream")
    # ... process tenant-specific data
```

**Adding a new tenant at runtime:**

```python
from dagster import DagsterInstance
instance = DagsterInstance.get()
instance.add_dynamic_partitions("tenant", ["new-customer"])
```

**Dagster UI** shows per-tenant run status — you can see which tenants are up to date and which have failed runs.

**Pros**: Single deployment, low cost, native Dagster support.

**Cons**: Noisy neighbor — one tenant's OOM or long-running job affects all tenants. No resource isolation.

### Medium: Dagster with Resource Limits

Same as above, but with per-tenant run configuration:

```python
@asset(
    partitions_def=tenants,
    op_tags={"dagster/concurrency_key": "tenant"},  # Limit concurrent runs per tenant
)
def event_stream(context):
    # ...
```

Combine with Dagster's run queue and concurrency limits to prevent one tenant from consuming all resources.

### Hard: Separate Dagster Deployments

One Dagster instance (ECS service or docker-compose stack) per tenant.

```bash
# Tenant A
docker compose --env-file .env.acme --project-name lakehouse-acme up -d

# Tenant B
docker compose --env-file .env.globex --project-name lakehouse-globex up -d
```

Each instance reads from its own catalog and writes to its own bucket. Complete isolation — one tenant's failure cannot affect another.

**Terraform can create the ECS services:**

```hcl
resource "aws_ecs_service" "dagster" {
  for_each      = toset(var.tenants)
  name          = "${var.project_name}-${each.key}-dagster"
  task_definition = aws_ecs_task_definition.dagster[each.key].arn
  # ... tenant-specific env vars (TENANT, LAKEHOUSE_BACKEND, bucket name)
}
```

**Costs**: ~$15-30/month per tenant (Fargate compute for webserver + daemon).

---

## Network Layer

Only relevant for Nessie deployments.

### Shared Nessie, Namespace Isolation

Single ALB, single ECS service. All tenants hit the same endpoint. Isolation is purely at the catalog namespace level.

**Cost**: Fixed (~$65-80/month regardless of tenant count).

**Risk**: A compromised Nessie instance exposes all tenants' catalog metadata.

### Path-Based Routing (Medium Isolation)

Single ALB with path-based listener rules routing to tenant-specific Nessie services:

```
https://nessie.internal/acme/api/v2  →  ECS Service: nessie-acme
https://nessie.internal/globex/api/v2 →  ECS Service: nessie-globex
```

**Cost**: ~$65-80/month per tenant (separate ECS services), shared ALB (~$16/month).

### Separate VPCs (Hard Isolation)

Each tenant gets its own VPC with its own Nessie deployment. The platform team accesses tenants via VPC peering or Transit Gateway.

**Cost**: Highest. Each VPC adds NAT gateway ($32/month), ALB ($16/month), and ECS costs.

**When to use**: When regulatory requirements mandate network-level isolation between tenants.

---

## Audit and Compliance

Multi-tenancy adds requirements to your audit trail:

### Tenant-Scoped Audit Logs

Every audit event should include the tenant identifier:

```python
log_audit_event("table_write", table="event_stream", details={
    "tenant": tenant,
    "row_count": len(df),
    "columns": list(df.columns),
})
```

### Separate Audit Trails (Medium/Hard)

For regulated workloads, each tenant may need their own audit trail:

- **Separate CloudTrail trails** per bucket (if using separate buckets)
- **Separate audit log buckets** per tenant
- **Log filters** by tenant prefix if using shared logging

This ensures tenant A's compliance auditor only sees tenant A's logs.

### Cross-Tenant Access Monitoring

Add a CloudWatch metric filter or Dagster sensor that alerts when a principal accesses data outside their assigned tenant:

```
Alert: IAM role "acme-reader" accessed object with prefix "globex/"
```

---

## Tenant Onboarding Workflow

Adding a new tenant should be a single PR:

### 1. Add Tenant Config

```yaml
# tenants/newcorp.yaml
tenant: newcorp
environment: prod
contact: ops@newcorp.com
access_overrides: {}
```

### 2. Terraform Creates Resources

```hcl
# Reads tenants/*.yaml just like table-templates/*.yaml
locals {
  tenants = {
    for f in fileset("${path.module}/../tenants", "*.yaml") :
    trimsuffix(f, ".yaml") => yamldecode(file("${path.module}/../tenants/${f}"))
  }
}
```

`terraform apply` creates the bucket, catalog database, IAM roles, and audit trail for the new tenant.

### 3. Dagster Picks Up the Tenant

If using dynamic partitions, add the tenant to the partition set. If using separate deployments, Terraform creates the ECS service.

### 4. CI Validates

Checkov scans verify the new tenant's resources follow the same security policies. Tests verify IAM isolation (tenant A's role cannot access tenant B's bucket).

---

## Decision Matrix

| Layer | Soft | Medium | Hard |
|-------|------|--------|------|
| **Storage** | Prefix isolation in shared bucket | Separate bucket per tenant | Separate AWS account per tenant |
| **Catalog** | Shared database, namespace prefix | Database per tenant | Catalog instance per tenant |
| **IAM** | Shared roles with prefix-scoped policies | Role set per tenant | Roles in separate accounts |
| **Pipelines** | Dagster partitions | Partitions + concurrency limits | Separate Dagster deployment |
| **Network** | Shared Nessie | Path-based ALB routing | Separate VPC per tenant |
| **Audit** | Shared trail with tenant field | Filtered views per tenant | Separate trails per tenant |
| **Onboarding** | Add namespace | Add YAML + `terraform apply` | New account + full stack |
| **Monthly cost per tenant** | ~$0 marginal | ~$5-15 (bucket + IAM) | ~$100+ (full infrastructure) |
| **Blast radius of misconfiguration** | Cross-tenant data leak | Scoped to one tenant's bucket | Contained to one AWS account |
