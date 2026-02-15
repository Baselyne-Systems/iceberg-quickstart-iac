# --- Storage (always created) ---

module "storage" {
  source = "./modules/storage"

  project_name      = var.project_name
  environment       = var.environment
  access_log_bucket = var.access_log_bucket
  enable_cloudtrail = var.enable_cloudtrail
}

# --- Glue Catalog (when catalog_type == "glue") ---

module "catalog_glue" {
  source = "./modules/catalog_glue"
  count  = var.catalog_type == "glue" ? 1 : 0

  project_name    = var.project_name
  environment     = var.environment
  bucket_name     = module.storage.bucket_name
  table_templates = local.table_templates
}

# --- Athena (when catalog_type == "glue") ---

module "athena" {
  source = "./modules/athena"
  count  = var.catalog_type == "glue" ? 1 : 0

  project_name       = var.project_name
  environment        = var.environment
  bucket_name        = module.storage.bucket_name
  glue_database_name = module.catalog_glue[0].database_name
  table_templates    = local.table_templates
}

# --- IAM / Lake Formation (when catalog_type == "glue") ---

module "iam" {
  source = "./modules/iam"
  count  = var.catalog_type == "glue" ? 1 : 0

  project_name          = var.project_name
  environment           = var.environment
  bucket_arn            = module.storage.bucket_arn
  glue_database_name    = module.catalog_glue[0].database_name
  table_templates       = local.table_templates
  restricted_columns    = local.restricted_columns
  lake_formation_admins = var.lake_formation_admins
}

# --- Networking (when catalog_type == "nessie") ---

module "networking" {
  source = "./modules/networking"
  count  = var.catalog_type == "nessie" ? 1 : 0

  project_name = var.project_name
  environment  = var.environment
  vpc_cidr     = var.vpc_cidr
  aws_region   = var.aws_region
}

# --- Nessie Catalog (when catalog_type == "nessie") ---

module "catalog_nessie" {
  source = "./modules/catalog_nessie"
  count  = var.catalog_type == "nessie" ? 1 : 0

  project_name     = var.project_name
  environment      = var.environment
  bucket_name      = module.storage.bucket_name
  bucket_arn       = module.storage.bucket_arn
  nessie_image_tag = var.nessie_image_tag
  vpc_id           = module.networking[0].vpc_id
  public_subnets   = module.networking[0].public_subnet_ids
  private_subnets  = module.networking[0].private_subnet_ids

  # Networking
  nessie_internal      = var.nessie_internal
  nessie_allowed_cidrs = var.nessie_allowed_cidrs
  certificate_arn      = var.certificate_arn

  # Compute
  nessie_cpu       = var.nessie_cpu
  nessie_memory    = var.nessie_memory
  nessie_min_count = var.nessie_min_count
  nessie_max_count = var.nessie_max_count

  # Monitoring & Logging
  alarm_sns_topic_arn   = var.alarm_sns_topic_arn
  alb_access_log_bucket = var.alb_access_log_bucket
  log_retention_days    = var.log_retention_days
}
