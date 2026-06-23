# nyc-taxi-glue-terraform

Terraform infrastructure for NYC taxi data Glue jobs. Deploys AWS resources automatically via Terraform Cloud whenever changes land on `dev` (dev environment) or `main` (prod environment).

## What this repo does

- Creates S3 buckets for Glue scripts and raw output data
- Creates the IAM execution role the Glue job uses at runtime
- Creates Glue job definitions pointing to scripts stored in S3
- All infrastructure is managed as code — no manual AWS console changes needed after bootstrap

## Repo structure

```
nyc-taxi-glue-terraform/
├── main.tf               # One module block per Glue job
├── terraform.tf          # Terraform Cloud backend + AWS provider
├── variables.tf          # aws_region, environment (values come from TFC workspace)
├── s3.tf                 # S3 buckets + env_suffix local
├── iam.tf                # Glue job execution role
├── modules/
│   └── glue_job/         # Reusable module — define once, call per job
│       ├── main.tf
│       ├── variables.tf
│       └── outputs.tf
├── iam/
│   └── bootstrap/        # One-time IAM setup — run once manually, not by Terraform
│       ├── tfc-oidc-trust-policy.json
│       └── tfc-deploy-permissions.json
├── docs/                 # Full setup and reference documentation
└── .github/
    └── workflows/
        └── terraform.yml # GitHub Actions — triggers TFC on push/PR to dev or main
```

## Branch strategy

```
feature/* ──→ PR ──→ dev ──→ PR ──→ main
                     │               │
                     ▼               ▼
               TFC: nyc-taxi-    TFC: nyc-taxi-
               glue-dev          glue-prod
               (resources get    (resources get
               -dev suffix)      no suffix)
```

- Work on feature branches
- PR to `dev` → runs `terraform plan` (preview only)
- Merge to `dev` → runs `terraform apply` → creates/updates dev AWS resources
- PR to `main` → runs `terraform plan` (review before prod)
- Merge to `main` → runs `terraform apply` → creates/updates prod AWS resources

## Documentation (read in order for first-time setup)

| # | Document | What it covers |
|---|----------|----------------|
| 1 | [Architecture](docs/01-architecture.md) | How all pieces connect end to end |
| 2 | [Prerequisites and tools](docs/02-prerequisites-and-tools.md) | AWS CLI, GitHub CLI, Terraform CLI setup |
| 3 | [AWS bootstrap](docs/03-aws-bootstrap.md) | One-time IAM roles and OIDC providers |
| 4 | [Terraform Cloud setup](docs/04-terraform-cloud-setup.md) | Workspace, dynamic credentials, API token |
| 5 | [GitHub Actions flow](docs/05-github-actions-flow.md) | How CI/CD triggers TFC and deploys to AWS |
| 6 | [Adding a new Glue job](docs/06-adding-a-new-glue-job.md) | Step-by-step guide for every new job |
| 7 | [Start from scratch](docs/07-start-from-scratch.md) | Full setup guide for a brand new account |

## Related repo

[nyc-taxi-glue](https://github.com/ranjanumesh11/nyc-taxi-glue) — Python scripts uploaded to S3, consumed by the Glue jobs defined here.

## Quick commands

```bash
# Authenticate AWS CLI (SSO — opens browser)
aws sso login --profile default

# Verify AWS identity
aws sts get-caller-identity --profile default

# Check Terraform version
terraform version

# List deployed Glue jobs
aws glue list-jobs --profile default

# List S3 buckets for this project
aws s3 ls --profile default | grep nyc-taxi
```
