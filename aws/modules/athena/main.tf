resource "aws_athena_workgroup" "lakehouse" {
  name = "${var.project_name}-${var.environment}-lakehouse"

  configuration {
    enforce_workgroup_configuration = true

    result_configuration {
      output_location = "s3://${var.bucket_name}/athena-results/"

      encryption_configuration {
        encryption_option = "SSE_KMS"
      }
    }

    engine_version {
      selected_engine_version = "Athena engine version 3"
    }
  }

  tags = {
    Name = "${var.project_name}-${var.environment}-lakehouse"
  }
}

# CREATE TABLE DDL for each Iceberg table
resource "aws_athena_named_query" "create_table" {
  for_each = var.table_templates

  name        = "create-${each.value.name}"
  description = "Create Iceberg table: ${each.value.name}"
  workgroup   = aws_athena_workgroup.lakehouse.id
  database    = var.glue_database_name

  query = <<-EOT
    CREATE TABLE IF NOT EXISTS ${var.glue_database_name}.${each.value.name} (
      ${join(",\n      ", [for col in each.value.columns : "${col.name} ${local.iceberg_to_athena_type[col.type]}"])}
    )
    PARTITIONED BY (${join(", ", [for p in each.value.partition_spec : "${p.transform}(${p.column})"])})
    LOCATION 's3://${var.bucket_name}/${each.value.namespace}/${each.value.name}/'
    TBLPROPERTIES (
      'table_type' = 'ICEBERG',
      'format' = '${try(each.value.properties.write_format, "parquet")}'
    )
  EOT
}

# Time-travel query examples
resource "aws_athena_named_query" "time_travel" {
  for_each = var.table_templates

  name        = "time-travel-${each.value.name}"
  description = "Time-travel example for: ${each.value.name}"
  workgroup   = aws_athena_workgroup.lakehouse.id
  database    = var.glue_database_name

  query = <<-EOT
    -- Snapshot history
    SELECT * FROM "${var.glue_database_name}"."${each.value.name}$snapshots"
    ORDER BY committed_at DESC
    LIMIT 10;

    -- Query as of a specific snapshot (replace <snapshot_id>)
    -- SELECT * FROM ${var.glue_database_name}.${each.value.name}
    -- FOR SYSTEM_VERSION AS OF <snapshot_id>
    -- LIMIT 100;
  EOT
}
