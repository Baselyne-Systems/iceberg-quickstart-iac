locals {
  # Map Iceberg types to Glue/Hive types
  iceberg_to_glue_type = {
    "boolean"     = "boolean"
    "int"         = "int"
    "long"        = "bigint"
    "float"       = "float"
    "double"      = "double"
    "date"        = "date"
    "time"        = "string"
    "timestamp"   = "timestamp"
    "timestamptz" = "timestamp"
    "string"      = "string"
    "uuid"        = "string"
    "binary"      = "binary"
  }
}
