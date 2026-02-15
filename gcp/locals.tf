locals {
  table_templates = {
    for f in fileset("${path.module}/../table-templates", "*.yaml") :
    trimsuffix(f, ".yaml") => yamldecode(file("${path.module}/../table-templates/${f}"))
    if f != "_schema.json"
  }

  restricted_columns = {
    for tbl_name, tbl in local.table_templates : tbl_name => [
      for col in tbl.columns : col.name
      if try(col.access_level, "public") == "restricted"
    ]
  }
}
