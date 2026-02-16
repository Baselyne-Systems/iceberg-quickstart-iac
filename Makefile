.PHONY: validate fmt plan-aws-glue plan-aws-nessie plan-aws-nessie-prod plan-gcp plan-aws-dev plan-aws-prod dagster-dev clean test security-scan audit-deps lock

validate:
	cd aws && terraform init -backend=false && terraform validate
	cd gcp && terraform init -backend=false && terraform validate

fmt:
	terraform fmt -recursive aws/
	terraform fmt -recursive gcp/

plan-aws-glue:
	cd aws && terraform init -backend=false && \
		terraform plan -var-file=../examples/aws-glue-quickstart.tfvars

plan-aws-nessie:
	cd aws && terraform init -backend=false && \
		terraform plan -var-file=../examples/aws-nessie-quickstart.tfvars

plan-aws-nessie-prod:
	cd aws && terraform init -backend=false && \
		terraform plan -var-file=../examples/aws-nessie-production.tfvars

plan-gcp:
	cd gcp && terraform init -backend=false && \
		terraform plan -var-file=../examples/gcp-quickstart.tfvars

plan-aws-dev:
	cd aws && terraform init -backend=false && \
		terraform plan -var-file=../environments/dev.tfvars

plan-aws-prod:
	cd aws && terraform init -backend=false && \
		terraform plan -var-file=../environments/prod.tfvars

dagster-dev:
	cd dagster && pip install -e ".[dev]" && dagster dev

lint:
	pre-commit run --all-files

test:
	bash tests/validate.sh
	cd dagster && python -m pytest lakehouse/tests/ -v

security-scan:
	checkov -d aws/ --config-file .checkov.yaml
	checkov -d gcp/ --config-file .checkov.yaml

audit-deps:
	cd dagster && uv run pip-audit

lock:
	cd dagster && uv lock

clean:
	rm -rf aws/.terraform gcp/.terraform
	rm -f aws/.terraform.lock.hcl gcp/.terraform.lock.hcl
