resource "aws_glue_catalog_database" "lakehouse" {
  name        = "${var.project_name}_${var.environment}"
  description = "Iceberg lakehouse catalog database"

  parameters = {
    "iceberg.catalog" = "glue"
  }

  lifecycle {
    prevent_destroy = true
  }
}

# Register Iceberg table shells in Glue.
# Partition specs are managed by Iceberg metadata, not Glue partition_keys.
resource "aws_glue_catalog_table" "tables" {
  for_each = var.table_templates

  database_name = aws_glue_catalog_database.lakehouse.name
  name          = each.value.name
  description   = try(each.value.description, "")
  table_type    = "EXTERNAL_TABLE"

  parameters = {
    "table_type"           = "ICEBERG"
    "metadata_location"    = "s3://${var.bucket_name}/${each.value.namespace}/${each.value.name}/metadata/"
    "classification"       = "iceberg"
    "write.format.default" = try(each.value.properties.write_format, "parquet")
  }

  storage_descriptor {
    location      = "s3://${var.bucket_name}/${each.value.namespace}/${each.value.name}/"
    input_format  = "org.apache.iceberg.mr.hive.HiveIcebergInputFormat"
    output_format = "org.apache.iceberg.mr.hive.HiveIcebergOutputFormat"

    ser_de_info {
      serialization_library = "org.apache.iceberg.mr.hive.HiveIcebergSerDe"
    }

    dynamic "columns" {
      for_each = each.value.columns
      content {
        name    = columns.value.name
        type    = local.iceberg_to_glue_type[columns.value.type]
        comment = try(columns.value.description, "")
      }
    }
  }

  lifecycle {
    ignore_changes = [
      parameters["metadata_location"],
    ]
  }
}
