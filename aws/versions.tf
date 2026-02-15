terraform {
  required_version = ">= 1.5"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  # Configure your backend per engagement:
  # backend "s3" {
  #   bucket         = "my-tf-state"
  #   key            = "iceberg-lakehouse/dev/terraform.tfstate"  # per-env: dev/, prod/, etc.
  #   region         = "us-east-1"
  #   dynamodb_table = "tf-locks"
  #   encrypt        = true
  # }
  # Tip: omit `key` here and pass it at init time for multi-env:
  #   terraform init -backend-config="key=iceberg-lakehouse/dev/terraform.tfstate"
  #   terraform init -reconfigure -backend-config="key=iceberg-lakehouse/prod/terraform.tfstate"
  # See docs/multi-environment.md for the full pattern.
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = var.project_name
      Environment = var.environment
      ManagedBy   = "terraform"
    }
  }
}
