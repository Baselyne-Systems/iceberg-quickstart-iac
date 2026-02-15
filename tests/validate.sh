#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"

echo "=== Terraform Validate (AWS) ==="
cd "$ROOT_DIR/aws"
terraform init -backend=false -input=false > /dev/null 2>&1
terraform validate

echo "=== Terraform Validate (GCP) ==="
cd "$ROOT_DIR/gcp"
terraform init -backend=false -input=false > /dev/null 2>&1
terraform validate

echo "=== Terraform Format Check ==="
cd "$ROOT_DIR"
terraform fmt -check -recursive aws/
terraform fmt -check -recursive gcp/

echo "=== All validations passed ==="
