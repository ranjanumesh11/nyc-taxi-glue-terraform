# nyc-taxi-glue-terraform

Terraform infrastructure for NYC taxi data Glue jobs. Deploys AWS resources automatically via Terraform Cloud when changes land on `master`.

## What this repo does

- Creates S3 buckets for Glue scripts and raw output data
- Creates the IAM execution role the Glue job uses at runtime
- Creates Glue job definitions pointing to scripts stored in S3
- All infrastructure is managed as code — no manual AWS console changes needed after bootstrap

## Repo structure

```
nyc-taxi-glue-terraform/
├── modules/
│   └── glue_job/           # Reusable module — defines one Glue job
│       ├── main.tf
│       ├── variables.tf
│       └── outputs.tf
├── environments/
│   └── dev/                # Dev environment — calls the module for each job
│       ├── terraform.tf    # Backend (Terraform Cloud) + provider config
│       ├── variables.tf
│       ├── s3.tf           # Scripts bucket + raw data bucket
│       ├── iam.tf          # Glue job execution role
│       └── main.tf         # One module block per Glue job
├── iam/
│   └── bootstrap/          # One-time IAM setup — run once, not by Terraform
│       ├── github-oidc-trust-policy.json
│       ├── github-deploy-permissions.json
│       ├── tfc-oidc-trust-policy.json
│       └── tfc-deploy-permissions.json
├── docs/                   # Detailed documentation
└── .github/
    └── workflows/
        └── terraform.yml   # GitHub Actions — triggers TFC on push to master
```

## Documentation (read in order for first-time setup)

| # | Document | What it covers |
|---|----------|----------------|
| 1 | [Architecture](docs/01-architecture.md) | How all pieces connect end to end |
| 2 | [Prerequisites and tools](docs/02-prerequisites-and-tools.md) | AWS CLI, GitHub CLI, Terraform CLI setup |
| 3 | [AWS bootstrap](docs/03-aws-bootstrap.md) | One-time IAM roles and OIDC providers |
| 4 | [Terraform Cloud setup](docs/04-terraform-cloud-setup.md) | Workspace, dynamic credentials, API token |
| 5 | [GitHub Actions flow](docs/05-github-actions-flow.md) | How CI/CD triggers TFC and deploys to AWS |
| 6 | [Adding a new Glue job](docs/06-adding-a-new-glue-job.md) | Step-by-step guide for every new job |

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
```
