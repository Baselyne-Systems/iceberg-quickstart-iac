module "storage" {
  source = "./modules/storage"

  project_name         = var.project_name
  environment          = var.environment
  gcp_location         = var.gcp_location
  gcp_project_id       = var.gcp_project_id
  enable_cmek          = var.enable_cmek
  enable_audit_logging = var.enable_audit_logging
}

module "biglake" {
  source = "./modules/biglake"

  project_name    = var.project_name
  environment     = var.environment
  gcp_location    = var.gcp_location
  bucket_name     = module.storage.bucket_name
  table_templates = local.table_templates
}

module "iam" {
  source = "./modules/iam"

  project_name       = var.project_name
  environment        = var.environment
  bucket_name        = module.storage.bucket_name
  dataset_id         = module.biglake.dataset_id
  restricted_columns = local.restricted_columns
}
