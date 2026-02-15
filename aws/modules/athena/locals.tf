locals {
  iceberg_to_athena_type = {
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
