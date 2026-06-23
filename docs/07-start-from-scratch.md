# Start From Scratch — Complete Setup Guide

This guide walks through rebuilding the entire setup from zero: a fresh AWS account, a new Terraform Cloud org, and two empty GitHub repos. Follow in order.

**Time to complete:** ~2–3 hours (most time is waiting for GitHub Actions runs and verifying each step).

---

## Prerequisites

### Tools to install

| Tool | Purpose | Install |
|------|---------|---------|
| AWS CLI v2 | All AWS operations | [docs.aws.amazon.com/cli](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html) |
| Terraform CLI | Local `fmt` and `validate` | [developer.hashicorp.com/terraform/install](https://developer.hashicorp.com/terraform/install) |
| GitHub CLI (`gh`) | Secrets, PRs, workflow runs | [cli.github.com](https://cli.github.com) |
| Git | Version control | [git-scm.com](https://git-scm.com) |

### Accounts to set up

| Account | URL | Notes |
|---------|-----|-------|
| AWS | [console.aws.amazon.com](https://console.aws.amazon.com) | Enable IAM Identity Center (SSO) for keyless local auth |
| Terraform Cloud | [app.terraform.io](https://app.terraform.io) | Free tier covers everything here |
| GitHub | [github.com](https://github.com) | Create two repos: `nyc-taxi-glue` and `nyc-taxi-glue-terraform` |

---

## Phase 1 — AWS local authentication

### Configure AWS SSO (IAM Identity Center)

This is the recommended way to authenticate locally — no long-lived access keys.

```powershell
# Configure SSO profile
aws configure sso

# When prompted:
# SSO start URL: your-org.awsapps.com/start  (from IAM Identity Center console)
# SSO region: us-east-1  (where your Identity Center is)
# SSO registration scopes: (press Enter for default)
# Account: select your account
# Role: AdministratorAccess (or equivalent)
# Profile name: default
```

Test it:
```powershell
aws sso login --profile default
aws sts get-caller-identity --profile default
```

Note your account ID — you'll need it throughout this guide.

---

## Phase 2 — GitHub repos and CLI auth

### Authenticate GitHub CLI

```powershell
gh auth login --hostname github.com --git-protocol https --web
```

### Create the two repos

```powershell
gh repo create nyc-taxi-glue --public --clone
gh repo create nyc-taxi-glue-terraform --public --clone
```

### Set up branches

```powershell
# In each repo:
cd nyc-taxi-glue
git checkout -b main
git push -u origin main
git checkout -b dev
git push -u origin dev

cd ..\nyc-taxi-glue-terraform
git checkout -b main
git push -u origin main
git checkout -b dev
git push -u origin dev
```

---

## Phase 3 — AWS bootstrap (one-time IAM setup)

These resources are created **once manually** — they cannot be managed by Terraform because they are the credentials Terraform needs to run.

### 3.1 — Create OIDC Identity Providers

OIDC providers let external systems (GitHub, Terraform Cloud) get temporary AWS credentials without storing access keys.

**GitHub Actions OIDC provider** (may already exist):
```powershell
aws iam create-open-id-connect-provider `
  --url https://token.actions.githubusercontent.com `
  --client-id-list sts.amazonaws.com `
  --thumbprint-list 6938fd4d98bab03faadb97b34396831e3780aea1 `
  --profile default
```

**Terraform Cloud OIDC provider:**
```powershell
aws iam create-open-id-connect-provider `
  --url https://app.terraform.io `
  --client-id-list aws.workload.identity `
  --thumbprint-list 9e99a48a9960b14926bb7f3b02e22da2b0ab7280 `
  --profile default
```

### 3.2 — Create the GitHub script deploy role

This role lets GitHub Actions upload Python scripts to S3.

Create the trust policy file `iam/bootstrap/github-oidc-trust-policy.json`:
```json
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Principal": {
      "Federated": "arn:aws:iam::<YOUR_ACCOUNT_ID>:oidc-provider/token.actions.githubusercontent.com"
    },
    "Action": "sts:AssumeRoleWithWebIdentity",
    "Condition": {
      "StringEquals": {
        "token.actions.githubusercontent.com:aud": "sts.amazonaws.com"
      },
      "StringLike": {
        "token.actions.githubusercontent.com:sub": "repo:<YOUR_GITHUB_USERNAME>/nyc-taxi-glue:ref:refs/heads/*"
      }
    }
  }]
}
```

Create the permissions file `iam/bootstrap/github-deploy-permissions.json`:
```json
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Action": ["s3:PutObject","s3:GetObject","s3:DeleteObject","s3:ListBucket"],
    "Resource": [
      "arn:aws:s3:::nyc-taxi-glue-scripts-<YOUR_ACCOUNT_ID>-dev",
      "arn:aws:s3:::nyc-taxi-glue-scripts-<YOUR_ACCOUNT_ID>-dev/*",
      "arn:aws:s3:::nyc-taxi-glue-scripts-<YOUR_ACCOUNT_ID>",
      "arn:aws:s3:::nyc-taxi-glue-scripts-<YOUR_ACCOUNT_ID>/*"
    ]
  }]
}
```

Create the role:
```powershell
cd nyc-taxi-glue  # the app repo

aws iam create-role `
  --role-name github-glue-script-deploy-role `
  --assume-role-policy-document file://iam/bootstrap/github-oidc-trust-policy.json `
  --profile default

aws iam put-role-policy `
  --role-name github-glue-script-deploy-role `
  --policy-name glue-script-s3-upload `
  --policy-document file://iam/bootstrap/github-deploy-permissions.json `
  --profile default
```

### 3.3 — Create the Terraform Cloud deploy role

This role lets TFC create AWS resources during plan/apply.

Create `iam/bootstrap/tfc-oidc-trust-policy.json`:
```json
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Principal": {
      "Federated": "arn:aws:iam::<YOUR_ACCOUNT_ID>:oidc-provider/app.terraform.io"
    },
    "Action": "sts:AssumeRoleWithWebIdentity",
    "Condition": {
      "StringEquals": {
        "app.terraform.io:aud": "aws.workload.identity"
      },
      "StringLike": {
        "app.terraform.io:sub": "organization:<YOUR_TFC_ORG>:project:*:workspace:nyc-taxi-glue-*:run_phase:*"
      }
    }
  }]
}
```

Create `iam/bootstrap/tfc-deploy-permissions.json`:
```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": ["glue:*","s3:*","logs:*"],
      "Resource": "*"
    },
    {
      "Effect": "Allow",
      "Action": ["iam:CreateRole","iam:DeleteRole","iam:GetRole","iam:PassRole",
                 "iam:PutRolePolicy","iam:DeleteRolePolicy","iam:GetRolePolicy",
                 "iam:AttachRolePolicy","iam:DetachRolePolicy","iam:ListAttachedRolePolicies",
                 "iam:ListRolePolicies","iam:TagRole","iam:UntagRole"],
      "Resource": "arn:aws:iam::<YOUR_ACCOUNT_ID>:role/nyc-taxi-*"
    }
  ]
}
```

Create the role:
```powershell
cd nyc-taxi-glue-terraform

aws iam create-role `
  --role-name terraform-cloud-deploy-role `
  --assume-role-policy-document file://iam/bootstrap/tfc-oidc-trust-policy.json `
  --profile default

aws iam put-role-policy `
  --role-name terraform-cloud-deploy-role `
  --policy-name glue-infra-deploy `
  --policy-document file://iam/bootstrap/tfc-deploy-permissions.json `
  --profile default
```

Verify both roles:
```powershell
aws iam get-role --role-name github-glue-script-deploy-role --profile default --query Role.Arn
aws iam get-role --role-name terraform-cloud-deploy-role --profile default --query Role.Arn
```

---

## Phase 4 — Terraform Cloud setup

### 4.1 — Create the organization

Go to [app.terraform.io](https://app.terraform.io) → **New organization**. Choose a unique name (e.g., `your-org-name`).

### 4.2 — Create workspaces

Create **two** workspaces: `nyc-taxi-glue-dev` and `nyc-taxi-glue-prod`.

For each workspace:
- Type: **CLI-driven workflow**
- After creation: go to **Settings → Tags** → add tag `nyc-taxi-glue` (key only, no value) → Save

### 4.3 — Configure workspace variables

On **each workspace** → **Variables**:

**Environment variables** (for OIDC auth):
| Key | Value |
|-----|-------|
| `TFC_AWS_PROVIDER_AUTH` | `true` |
| `TFC_AWS_RUN_ROLE_ARN` | `arn:aws:iam::<ACCOUNT_ID>:role/terraform-cloud-deploy-role` |

**Terraform variables** (HCL checkbox = **unchecked**):
| Key | Value in `nyc-taxi-glue-dev` | Value in `nyc-taxi-glue-prod` |
|-----|-----|------|
| `aws_region` | `us-east-1` | `us-east-1` |
| `environment` | `dev` | *(empty string)* |

### 4.4 — Create TFC API token

Go to [app.terraform.io](https://app.terraform.io) → avatar → **User settings** → **Tokens** → **Create an API token**.
Name it `github-actions`. Copy the token value.

In your terminal:
```powershell
$env:TFC_TOKEN = "paste-token-here"
gh secret set TFC_API_TOKEN --body $env:TFC_TOKEN --repo <YOUR_GITHUB_USERNAME>/nyc-taxi-glue-terraform
```

---

## Phase 5 — Terraform code (infrastructure repo)

Copy the Terraform files into `nyc-taxi-glue-terraform/`. At repo root you need:

**`terraform.tf`** — Terraform Cloud backend + provider:
```hcl
terraform {
  required_version = ">= 1.6"
  cloud {
    organization = "<YOUR_TFC_ORG>"
    workspaces {
      tags = ["nyc-taxi-glue"]
    }
  }
  required_providers {
    aws = { source = "hashicorp/aws", version = "~> 5.0" }
  }
}
provider "aws" {
  region = var.aws_region
}
```

**`variables.tf`**:
```hcl
variable "aws_region" {
  type        = string
  description = "AWS region"
}
variable "environment" {
  type        = string
  description = "dev → resources get -dev suffix. Empty string → prod (no suffix)"
}
```

**`s3.tf`** — buckets + env_suffix local:
```hcl
data "aws_caller_identity" "current" {}

locals {
  account_id      = data.aws_caller_identity.current.account_id
  env_suffix      = var.environment != "" ? "-${var.environment}" : ""
  scripts_bucket  = "nyc-taxi-glue-scripts-${local.account_id}${local.env_suffix}"
  raw_data_bucket = "nyc-taxi-raw-data-${local.account_id}${local.env_suffix}"
  common_tags = {
    Environment = coalesce(var.environment, "prod")
    Project     = "nyc-taxi"
    ManagedBy   = "terraform"
  }
}

resource "aws_s3_bucket" "glue_scripts" {
  bucket = local.scripts_bucket
  tags   = local.common_tags
}
resource "aws_s3_bucket_versioning" "glue_scripts" {
  bucket = aws_s3_bucket.glue_scripts.id
  versioning_configuration { status = "Enabled" }
}
resource "aws_s3_bucket_public_access_block" "glue_scripts" {
  bucket                  = aws_s3_bucket.glue_scripts.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket" "raw_data" {
  bucket = local.raw_data_bucket
  tags   = local.common_tags
}
resource "aws_s3_bucket_versioning" "raw_data" {
  bucket = aws_s3_bucket.raw_data.id
  versioning_configuration { status = "Enabled" }
}
resource "aws_s3_bucket_public_access_block" "raw_data" {
  bucket                  = aws_s3_bucket.raw_data.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}
```

**`iam.tf`** — Glue execution role (Terraform manages this one):
```hcl
resource "aws_iam_role" "glue_execution" {
  name = "nyc-taxi-glue-execution-role${local.env_suffix}"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "glue.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
  tags = local.common_tags
}

resource "aws_iam_role_policy" "glue_s3" {
  name = "glue-s3-access"
  role = aws_iam_role.glue_execution.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["s3:GetObject", "s3:ListBucket"]
        Resource = [
          aws_s3_bucket.glue_scripts.arn,
          "${aws_s3_bucket.glue_scripts.arn}/*"
        ]
      },
      {
        Effect   = "Allow"
        Action   = ["s3:PutObject", "s3:GetObject", "s3:DeleteObject", "s3:ListBucket"]
        Resource = [
          aws_s3_bucket.raw_data.arn,
          "${aws_s3_bucket.raw_data.arn}/*"
        ]
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "glue_service" {
  role       = aws_iam_role.glue_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSGlueServiceRole"
}
```

**`main.tf`** — Glue job definitions:
```hcl
module "yellow_taxi_april_2026_download" {
  source = "./modules/glue_job"

  job_name        = "yellow-taxi-april-2026-download${local.env_suffix}"
  description     = "Downloads NYC yellow taxi April 2026 parquet from TLC to S3"
  role_arn        = aws_iam_role.glue_execution.arn
  script_location = "s3://${aws_s3_bucket.glue_scripts.bucket}/scripts/yellow_taxi/download_yellow_taxi_april_2026.py"

  default_arguments = {
    "--output_bucket" = aws_s3_bucket.raw_data.bucket
    "--output_prefix" = "yellow/2026/04"
  }

  tags = local.common_tags
}
```

Create `modules/glue_job/` — see the repo for the full module code.

**`.github/workflows/terraform.yml`**:
```yaml
name: Terraform
on:
  push:
    branches: [main, dev]
  pull_request:
    branches: [main, dev]
permissions:
  contents: read
  pull-requests: write
jobs:
  terraform:
    name: Plan & Apply
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Select TFC workspace
        run: |
          TARGET="${{ github.base_ref || github.ref_name }}"
          if [ "$TARGET" = "main" ]; then
            echo "TF_WORKSPACE=nyc-taxi-glue-prod" >> $GITHUB_ENV
          else
            echo "TF_WORKSPACE=nyc-taxi-glue-dev" >> $GITHUB_ENV
          fi
      - uses: hashicorp/setup-terraform@v3
        with:
          cli_config_credentials_token: ${{ secrets.TFC_API_TOKEN }}
      - run: terraform init
      - run: terraform fmt -check -recursive
      - run: terraform validate
      - run: terraform plan -no-color
      - name: Terraform Apply
        if: github.event_name == 'push'
        run: terraform apply -auto-approve
```

---

## Phase 6 — GitHub Actions secrets and variables

### For nyc-taxi-glue (app repo)

**Secrets:**
```powershell
$env:ACCOUNT_ID = "YOUR_ACCOUNT_ID"
gh secret set AWS_ACCOUNT_ID --body $env:ACCOUNT_ID --repo <USER>/nyc-taxi-glue
```

**Variables** (not sensitive — use `gh variable set`):
```powershell
gh variable set AWS_REGION --body "us-east-1" --repo <USER>/nyc-taxi-glue
gh variable set GLUE_SCRIPTS_BUCKET_DEV --body "nyc-taxi-glue-scripts-<ACCOUNT_ID>-dev" --repo <USER>/nyc-taxi-glue
gh variable set GLUE_SCRIPTS_BUCKET_PROD --body "nyc-taxi-glue-scripts-<ACCOUNT_ID>" --repo <USER>/nyc-taxi-glue
```

### For nyc-taxi-glue-terraform

Only one secret needed (already done in Phase 4):
```
TFC_API_TOKEN
```

---

## Phase 7 — Deploy infrastructure

Commit all terraform files and push to the feature branch, then open a PR to `dev`:

```powershell
cd nyc-taxi-glue-terraform
git checkout -b feature/initial-setup
git add .
git commit -m "feat: initial infrastructure setup"
git push -u origin feature/initial-setup
gh pr create --base dev --title "feat: initial infrastructure" --body "Initial S3, IAM, and Glue job setup"
```

When the PR runs, check the **Checks** tab — you should see `terraform plan` with 9 resources to add. Merge the PR to trigger `terraform apply`.

Verify AWS resources were created:
```powershell
aws glue list-jobs --profile default
aws s3 ls --profile default | Select-String "nyc-taxi"
```

---

## Phase 8 — Deploy the Python script

In `nyc-taxi-glue`, add the script and push to `dev`:

```powershell
cd nyc-taxi-glue
# copy the download_yellow_taxi_april_2026.py script to scripts/yellow_taxi/
git add scripts/
git commit -m "feat: add yellow taxi April 2026 download script"
git push origin dev
```

This triggers the GitHub Actions workflow to upload the script to S3 (because `scripts/**` changed on `dev`).

Verify:
```powershell
aws s3 ls s3://nyc-taxi-glue-scripts-<ACCOUNT_ID>-dev/scripts/ --recursive --profile default
```

---

## Phase 9 — Run the Glue job

```powershell
# Start the job
aws glue start-job-run `
  --job-name "yellow-taxi-april-2026-download-dev" `
  --profile default

# Monitor (run this a few times until State = SUCCEEDED)
aws glue get-job-runs `
  --job-name "yellow-taxi-april-2026-download-dev" `
  --profile default `
  --query "JobRuns[0].{State:JobRunState,Duration:ExecutionTime}"

# Verify the downloaded file in S3
aws s3 ls s3://nyc-taxi-raw-data-<ACCOUNT_ID>-dev/yellow/2026/04/ --profile default
```

A 68 MB parquet file (`yellow_tripdata_2026-04.parquet`) should appear.

---

## Phase 10 — Promote to prod

Open PR `dev → main` on both repos. Merging creates prod AWS resources (no `-dev` suffix) and uploads the script to the prod S3 bucket.

Before merging the terraform PR, ensure the `nyc-taxi-glue-prod` TFC workspace exists with:
- Tag `nyc-taxi-glue` applied
- Same env vars as dev workspace, but `environment = ""` (empty string, no HCL checkbox)

---

## Cost summary

| Resource | Ongoing idle cost | Per-run cost |
|----------|------------------|-------------|
| S3 buckets | Free | — |
| S3 storage (~70 MB) | ~$0.002/month | — |
| Glue job definition | Free | — |
| Glue job run (0.0625 DPU, ~3 min) | — | ~$0.001 |
| IAM roles, OIDC providers | Free | — |
| Terraform Cloud (free tier) | Free | — |
| GitHub Actions (public repo) | Free | — |

**Total idle cost: effectively $0/month.** Running the Glue job once costs less than a tenth of a cent.

---

## Troubleshooting common errors

| Error | Cause | Fix |
|-------|-------|-----|
| `unauthorized` on TFC init | `TFC_API_TOKEN` secret invalid or expired | Regenerate token in TFC UI → set new secret |
| `invalid HCL` for `TFC_AWS_RUN_ROLE_ARN` | Set as Terraform variable (not Environment variable) | Delete and re-add as **Environment variable** |
| `Variables not allowed` for `aws_region` | HCL checkbox is checked | Uncheck HCL checkbox on both Terraform variables |
| `lstat ../../modules: no such file or directory` | Running `terraform` from a subdirectory — TFC only uploads that dir | Run from repo root so `modules/` is included in the upload |
| `workspace not found` | TFC workspace missing the `nyc-taxi-glue` tag | In TFC UI → Workspace settings → Tags → add `nyc-taxi-glue` |
| GitHub Actions not triggering | Pushed only non-script files (path filter) | Use `workflow_dispatch` or make a change inside `scripts/` |
| AWS auth fails in GitHub Actions | Trust policy scoped to wrong branch | Update trust policy: `ref:refs/heads/*` for all branches |
