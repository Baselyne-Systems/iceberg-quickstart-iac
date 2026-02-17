# Multi-Tenancy Guide

How to give different teams different levels of access to shared lakehouse tables.

---

## The Problem

The default setup creates three global roles: reader, writer, admin. Everyone with the reader role gets the same view of every table. Everyone with the writer role can write to every table.

This breaks down quickly:

- The **analytics team** should read `event_stream` and `scd_type2` but has no business writing to them
- The **data engineering team** owns `event_stream` and should be the only team that writes to it
- The **ML team** needs write access to `feature_table` but only read access to everything else
- The **customer team** owns `scd_type2` and needs to see the `email` column (PII), but the analytics team shouldn't

The answer isn't separate buckets or separate catalogs — the tables are shared. The answer is **per-team access levels on each table**.

---

## How It Works

### 1. Table Templates Already Have Domains

Each table template has a `tags.domain` field:

```yaml
# table-templates/event_stream.yaml
tags:
  domain: analytics

# table-templates/scd_type2.yaml
tags:
  domain: master-data

# table-templates/feature_table.yaml
tags:
  domain: ml
```

### 2. Add a Teams Configuration

Create `teams/` directory with one YAML per team:

```yaml
# teams/data-engineering.yaml
name: data-engineering
description: Owns ingestion pipelines and event data

# Per-table access. Missing tables default to "none".
tables:
  event_stream: writer       # Owns this table — can read and write
  scd_type2: reader          # Can read, no PII access
  feature_table: reader      # Can read, no PII access
```

```yaml
# teams/analytics.yaml
name: analytics
description: BI dashboards and ad-hoc analysis

tables:
  event_stream: reader       # Read, no PII columns
  scd_type2: reader          # Read, no PII columns
  feature_table: none        # No access
```

```yaml
# teams/ml-platform.yaml
name: ml-platform
description: ML feature engineering and model training

tables:
  event_stream: reader       # Read events for feature computation
  scd_type2: reader          # Read dimensions
  feature_table: writer      # Owns this table
```

```yaml
# teams/customer-data.yaml
name: customer-data
description: Owns customer master data

tables:
  event_stream: none         # No access
  scd_type2: writer          # Owns this table — full access including PII
  feature_table: none        # No access
```

```yaml
# teams/platform.yaml
name: platform
description: Infrastructure and platform team

tables:
  event_stream: admin
  scd_type2: admin
  feature_table: admin
```

### 3. Access Levels Per Table

| Level | S3/GCS | Catalog (SELECT) | Catalog (INSERT/DELETE) | PII Columns | ALTER |
|-------|--------|-----------------|----------------------|-------------|-------|
| `none` | No access | No | No | No | No |
| `reader` | Read data files | Yes (public columns) | No | Excluded | No |
| `writer` | Read + write | Yes (all columns) | Yes | Full access | No |
| `admin` | Full | Yes (all columns) | Yes | Full access | Yes |

A team with `writer` on `event_stream` and `reader` on `scd_type2` can:
- Read and write event_stream data, see PII columns in event_stream
- Read scd_type2 data but not the `email` column, cannot write

---

## Terraform Implementation

### Load Teams Config

```hcl
# In locals.tf, alongside table template loading
locals {
  teams = {
    for f in fileset("${path.module}/../teams", "*.yaml") :
    trimsuffix(f, ".yaml") => yamldecode(file("${path.module}/../teams/${f}"))
  }

  # Build a flat map of { "team-table" => access_level }
  team_table_access = merge([
    for team_key, team in local.teams : {
      for table_key, access in try(team.tables, {}) :
      "${team_key}-${table_key}" => {
        team       = team_key
        team_name  = team.name
        table      = table_key
        access     = access
      }
      if access != "none"
    }
  ]...)
}
```

### Create IAM Roles Per Team

```hcl
resource "aws_iam_role" "team" {
  for_each = local.teams
  name     = "${var.project_name}-${var.environment}-${each.key}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root" }
    }]
  })

  tags = {
    Team = each.value.name
  }
}
```

### Lake Formation Permissions Per Team Per Table

```hcl
# Reader-level: SELECT on public columns only
resource "aws_lakeformation_permissions" "team_reader" {
  for_each = {
    for k, v in local.team_table_access : k => v
    if v.access == "reader"
  }

  principal   = aws_iam_role.team[each.value.team].arn
  permissions = ["SELECT"]

  table_with_columns {
    database_name         = var.glue_database_name
    name                  = var.table_templates[each.value.table].name
    excluded_column_names = try(var.restricted_columns[each.value.table], [])
  }
}

# Writer-level: SELECT + INSERT + DELETE on all columns
resource "aws_lakeformation_permissions" "team_writer" {
  for_each = {
    for k, v in local.team_table_access : k => v
    if v.access == "writer"
  }

  principal   = aws_iam_role.team[each.value.team].arn
  permissions = ["SELECT", "INSERT", "DELETE"]

  table_with_columns {
    database_name = var.glue_database_name
    name          = var.table_templates[each.value.table].name
    wildcard      = true
  }
}

# Admin-level: ALL on the full database
resource "aws_lakeformation_permissions" "team_admin" {
  for_each = {
    for k, v in local.team_table_access : k => v
    if v.access == "admin"
  }

  principal   = aws_iam_role.team[each.value.team].arn
  permissions = ["ALL"]

  table_with_columns {
    database_name = var.glue_database_name
    name          = var.table_templates[each.value.table].name
    wildcard      = true
  }
}
```

### GCP: Service Accounts Per Team

Same pattern — one service account per team, BigQuery dataset-level and Data Catalog policy tag permissions scoped by access level:

```hcl
resource "google_service_account" "team" {
  for_each     = local.teams
  account_id   = "${var.project_name}-${var.environment}-${each.key}"
  display_name = each.value.name
}

# Writer teams get categoryFineGrainedReader (can see restricted columns)
resource "google_data_catalog_taxonomy_iam_member" "team_restricted" {
  for_each = {
    for k, v in local.team_table_access : v.team => v...
    if v.access == "writer" || v.access == "admin"
  }

  taxonomy = google_data_catalog_taxonomy.lakehouse.id
  role     = "roles/datacatalog.categoryFineGrainedReader"
  member   = "serviceAccount:${google_service_account.team[each.key].email}"
}
```

---

## Dagster Implementation

### Team Context in the IO Manager

The IO manager needs to know which team is running the current job to enforce the correct access level per table:

```python
# Set via environment variable
LAKEHOUSE_TEAM=data-engineering dagster dev
```

The IO manager reads the team config and determines access per table:

```python
def _get_team_access(team: str, table_name: str) -> str:
    """Return access level for a team on a specific table."""
    teams_dir = Path(__file__).parent.parent.parent.parent / "teams"
    team_file = teams_dir / f"{team}.yaml"
    if not team_file.exists():
        return "none"
    team_config = yaml.safe_load(team_file.read_text())
    return team_config.get("tables", {}).get(table_name, "none")
```

In `load_input`:

```python
team = os.environ.get("LAKEHOUSE_TEAM", "platform")
access = _get_team_access(team, table_name)

if access == "none":
    raise PermissionError(f"Team '{team}' has no access to table '{table_name}'")

if access == "reader":
    # Drop restricted columns (existing PII masking logic)
    restricted = get_restricted_columns(template)
    result = result.drop([c for c in restricted if c in result.column_names])
```

In `handle_output`:

```python
team = os.environ.get("LAKEHOUSE_TEAM", "platform")
access = _get_team_access(team, table_name)

if access not in ("writer", "admin"):
    raise PermissionError(f"Team '{team}' cannot write to table '{table_name}'")
```

### Per-Team Dagster Deployments

For production, each team runs their own Dagster instance with their team's IAM role and `LAKEHOUSE_TEAM` set:

```bash
# Data engineering team
docker compose --env-file .env.data-engineering --project-name dagster-data-eng up -d

# ML team
docker compose --env-file .env.ml-platform --project-name dagster-ml up -d
```

Each `.env` file sets:

```bash
LAKEHOUSE_TEAM=data-engineering
AWS_ROLE_ARN=arn:aws:iam::123456789012:role/myproject-prod-data-engineering
```

The IAM role enforces access at the cloud layer. The Dagster team context enforces it at the application layer. Both agree because they both read from the same `teams/*.yaml` config.

---

## Table Ownership

Add an `owner` field to table templates to make ownership explicit:

```yaml
# table-templates/event_stream.yaml
name: event_stream
owner: data-engineering      # Only this team should write
tags:
  domain: analytics
```

This is informational today — ownership is enforced by the `writer` access level in the team config. But making it explicit in the template:

- Documents who to contact when the table has issues
- Can drive Dagster alerts (schema drift on `event_stream` → notify `data-engineering`)
- Makes access reviews easier ("does the team config match the ownership?")

---

## Shared Tables vs Team Tables

Most tables in a lakehouse are **shared** — multiple teams read from them. But some teams may create tables only they use (staging tables, experiment results, scratch datasets).

### Option A: Namespace Convention

```yaml
# Shared tables: namespace = "lakehouse"
namespace: lakehouse

# Team-specific tables: namespace = "team-{name}"
namespace: team-ml
```

Team-specific namespaces get automatic access restrictions: only the owning team + platform has access.

### Option B: Domain Tags

Use the existing `tags.domain` field. The team config already maps tables to access levels — team-only tables simply have `none` for all other teams.

Option B is simpler and doesn't require new Terraform logic. Namespaces add a layer of catalog organization if you have many team-specific tables.

---

## Onboarding a New Team

1. Create `teams/new-team.yaml` with their table access levels
2. Run `terraform apply` — creates IAM role + Lake Formation permissions
3. Create a `.env.new-team` in `dagster/` with their role ARN and team name
4. Start their Dagster instance (or add them to the shared one)

Removing a team: delete the YAML, `terraform apply` removes the role and permissions.

Changing access: edit the YAML, `terraform apply` updates Lake Formation permissions. No manual IAM work.

---

## Access Review

The teams config is version-controlled. An access review is a PR review:

```
"Does the analytics team really need reader access to feature_table?"
"The customer-data team has writer on scd_type2 — is that still correct?"
```

To generate a summary of who has access to what:

```bash
# Quick audit: print the access matrix
python3 -c "
import yaml
from pathlib import Path

teams_dir = Path('teams')
for f in sorted(teams_dir.glob('*.yaml')):
    team = yaml.safe_load(f.read_text())
    print(f\"\n{team['name']}:\")
    for table, access in sorted(team.get('tables', {}).items()):
        print(f\"  {table}: {access}\")
"
```

Output:

```
analytics:
  event_stream: reader
  scd_type2: reader

customer-data:
  scd_type2: writer

data-engineering:
  event_stream: writer
  feature_table: reader
  scd_type2: reader

ml-platform:
  event_stream: reader
  feature_table: writer
  scd_type2: reader

platform:
  event_stream: admin
  feature_table: admin
  scd_type2: admin
```

This is your access matrix. Review it quarterly.

---

## What Stays Shared

Multi-tenancy for internal teams does **not** mean duplicating infrastructure:

| Component | Shared? | Why |
|-----------|---------|-----|
| S3/GCS bucket | Yes | One bucket, shared data. Teams access the same Parquet files. |
| Catalog (Glue/Nessie/BigLake) | Yes | One database, shared table definitions. |
| Table templates | Yes | Tables are shared resources. Templates are the source of truth. |
| Dagster codebase | Yes | Same assets, same sensors. Teams run different instances with different roles. |
| CI/CD pipeline | Yes | One pipeline validates everything. |
| Audit trail | Yes | One CloudTrail, one log sink. Audit events include team name for filtering. |
| Schema drift sensor | Yes | Monitors all tables regardless of ownership. Alerts route to the owning team. |

What's per-team: IAM roles, Lake Formation permissions, Dagster env files, and alert routing.
