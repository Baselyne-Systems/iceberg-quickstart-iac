terraform {
  required_version = ">= 1.5"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
    google-beta = {
      source  = "hashicorp/google-beta"
      version = "~> 5.0"
    }
  }

  # Configure your backend per engagement:
  # backend "gcs" {
  #   bucket = "my-tf-state"
  #   prefix = "iceberg-lakehouse/dev"  # per-env: dev/, prod/, etc.
  # }
  # Tip: omit `prefix` here and pass it at init time for multi-env:
  #   terraform init -backend-config="prefix=iceberg-lakehouse/dev"
  #   terraform init -reconfigure -backend-config="prefix=iceberg-lakehouse/prod"
  # See docs/multi-environment.md for the full pattern.
}

provider "google" {
  project = var.gcp_project_id
  region  = var.gcp_region
}

provider "google-beta" {
  project = var.gcp_project_id
  region  = var.gcp_region
}
