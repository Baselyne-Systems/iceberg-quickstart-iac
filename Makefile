.PHONY: validate fmt plan-aws-glue plan-aws-nessie plan-aws-nessie-prod plan-gcp dagster-dev clean test

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

dagster-dev:
	cd dagster && pip install -e ".[dev]" && dagster dev

lint:
	pre-commit run --all-files

test:
	bash tests/validate.sh
	cd dagster && python -m pytest lakehouse/tests/ -v

clean:
	rm -rf aws/.terraform gcp/.terraform
	rm -f aws/.terraform.lock.hcl gcp/.terraform.lock.hcl
