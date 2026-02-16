# Secrets Management Guide

How to handle credentials, API keys, and other secrets across local development, CI/CD, and production.

---

## Why `.env` Files Aren't Enough

`.env` files are plaintext on disk. One `git add -A` away from being committed. They work for local dev, but in production:

- No audit trail of who accessed what
- No rotation without redeploying
- No encryption at rest (unless you encrypt the whole filesystem)
- Shared credentials become impossible to revoke per-person

Use `.env` files locally. Use a secrets manager in production.

---

## AWS Secrets Manager

Best for: secrets that rotate (database passwords, API keys, tokens).

### Store a secret

```bash
aws secretsmanager create-secret \
  --name lakehouse/prod/nessie-token \
  --secret-string '{"token":"your-secret-value"}'
```

### Reference from ECS task definitions

```json
{
  "containerDefinitions": [{
    "secrets": [{
      "name": "NESSIE_TOKEN",
      "valueFrom": "arn:aws:secretsmanager:us-east-1:123456789012:secret:lakehouse/prod/nessie-token"
    }]
  }]
}
```

### Fetch at Dagster startup

```python
import boto3, json

def get_secret(name: str) -> dict:
    client = boto3.client("secretsmanager")
    resp = client.get_secret_value(SecretId=name)
    return json.loads(resp["SecretString"])
```

### Enable automatic rotation

```bash
aws secretsmanager rotate-secret \
  --secret-id lakehouse/prod/nessie-token \
  --rotation-lambda-arn arn:aws:lambda:us-east-1:123456789012:function:rotate-nessie
```

---

## AWS SSM Parameter Store

Best for: non-rotating config values (endpoint URLs, feature flags, environment names). Free tier covers most use cases.

### Store a parameter

```bash
# Plaintext (non-sensitive config)
aws ssm put-parameter \
  --name /lakehouse/prod/nessie-uri \
  --type String \
  --value "https://nessie.internal.example.com/api/v2"

# Encrypted (sensitive values)
aws ssm put-parameter \
  --name /lakehouse/prod/db-password \
  --type SecureString \
  --value "hunter2"
```

### Fetch in application code

```python
import boto3

ssm = boto3.client("ssm")
resp = ssm.get_parameter(Name="/lakehouse/prod/nessie-uri", WithDecryption=True)
value = resp["Parameter"]["Value"]
```

---

## Local Development

### Use `aws-vault` for credential isolation

`aws-vault` stores AWS credentials in your OS keychain instead of `~/.aws/credentials`:

```bash
brew install aws-vault

# Add your profile
aws-vault add dev-account

# Run commands with temporary credentials (never touches disk)
aws-vault exec dev-account -- terraform plan
aws-vault exec dev-account -- dagster dev
```

### Use `granted` for multi-account access

```bash
brew install common-fate/granted/granted

# Assume a role interactively
assume dev-account
```

Both tools avoid long-lived IAM access keys on your laptop.

---

## CI/CD — GitHub OIDC Federation

Instead of storing AWS access keys as GitHub secrets, use OIDC federation. GitHub issues a short-lived token that AWS trusts directly.

### 1. Create the OIDC provider (one-time, via Terraform or CLI)

```bash
aws iam create-open-id-connect-provider \
  --url https://token.actions.githubusercontent.com \
  --thumbprint-list 6938fd4d98bab03faadb97b34396831e3780aea1 \
  --client-id-list sts.amazonaws.com
```

### 2. Create a role that trusts GitHub

```json
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Principal": {
      "Federated": "arn:aws:iam::ACCOUNT_ID:oidc-provider/token.actions.githubusercontent.com"
    },
    "Action": "sts:AssumeRoleWithWebIdentity",
    "Condition": {
      "StringEquals": {
        "token.actions.githubusercontent.com:aud": "sts.amazonaws.com"
      },
      "StringLike": {
        "token.actions.githubusercontent.com:sub": "repo:your-org/iceberg-quickstart-iac:*"
      }
    }
  }]
}
```

### 3. Use in GitHub Actions

```yaml
permissions:
  id-token: write
  contents: read

steps:
  - uses: aws-actions/configure-aws-credentials@v4
    with:
      role-to-assume: arn:aws:iam::ACCOUNT_ID:role/github-ci
      aws-region: us-east-1
```

No static credentials stored anywhere.

---

## Anti-Patterns

| Practice | Why it's bad | What to do instead |
|----------|-------------|-------------------|
| Committing `.env` files | Plaintext secrets in version history forever | Use `.env.example` with placeholders; real values from secrets manager |
| IAM user access keys in prod | Long-lived, can't be scoped to a session, hard to rotate | Use IAM roles with temporary credentials (STS AssumeRole) |
| Shared credentials | Can't revoke one person without affecting everyone | Per-developer IAM users locally, per-service IAM roles in prod |
| Hardcoded secrets in Terraform | Stored in state file (plaintext by default) | Use `data "aws_secretsmanager_secret_version"` to reference, never inline |
| GitHub secrets for AWS keys | Static keys that persist until manually rotated | OIDC federation (see above) |
