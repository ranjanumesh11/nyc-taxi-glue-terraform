# Terraform Cloud Setup

## Account and organization

| Item | Value |
|------|-------|
| Platform | [app.terraform.io](https://app.terraform.io) |
| Organization | `demo-kt-101` |
| Dev workspace | `nyc-taxi-glue-dev` |
| Prod workspace | `nyc-taxi-glue-prod` |
| Workspace type | CLI-driven |

---

## Why Terraform Cloud

Terraform Cloud handles:
- Remote state storage (no S3 backend or local `.tfstate` files)
- Remote plan/apply execution (not on GitHub runner or your laptop)
- State locking (prevents two runs colliding)
- Run history and audit log

---

## Two workspaces, one codebase

The same Terraform code at repo root deploys to either dev or prod depending on which workspace is selected. The GitHub Actions workflow sets `TF_WORKSPACE` based on the target branch:

| Branch | TFC Workspace | AWS resources |
|--------|--------------|---------------|
| `dev` | `nyc-taxi-glue-dev` | Suffix `-dev` on all names |
| `main` | `nyc-taxi-glue-prod` | No suffix (prod) |

`TF_WORKSPACE` is an environment variable the Terraform CLI reads. The `terraform.tf` cloud block uses `workspaces { tags = ["nyc-taxi-glue"] }` (not a hardcoded workspace name), which makes the tag-based lookup work with `TF_WORKSPACE`.

Both workspaces must have the `nyc-taxi-glue` tag applied in TFC UI → Workspace settings → Tags.

---

## Dynamic credentials — how TFC authenticates to AWS

No AWS access keys are stored in TFC. Instead, TFC uses OIDC to get temporary credentials for every run.

### The flow step by step

```
Terraform run starts in TFC
         │
         ▼
TFC generates a short-lived OIDC JWT
(valid ~5 minutes, just for the handshake)
         │
         ▼
TFC calls AWS STS: AssumeRoleWithWebIdentity
  - Role: arn:aws:iam::721559935914:role/terraform-cloud-deploy-role
  - JWT audience: aws.workload.identity
         │
         ▼
AWS checks the app.terraform.io OIDC provider:
  - Is the JWT signature valid? ✓
  - Does sub match organization:demo-kt-101:project:*:workspace:nyc-taxi-glue-*:run_phase:*? ✓
         │
         ▼
AWS STS returns temporary credentials
  AWS_ACCESS_KEY_ID + AWS_SECRET_ACCESS_KEY + AWS_SESSION_TOKEN
  Valid for: 1 hour
         │
         ▼
TFC injects credentials as env vars into the run
         │
         ▼
Terraform AWS provider calls AWS using those credentials
         │
         ▼
Run completes → credentials expire automatically → nothing to clean up
```

### Workspace variables that enable this

Set on **each workspace** under **Variables → Environment variables**:

| Key | Value | Sensitive | Note |
|-----|-------|-----------|------|
| `TFC_AWS_PROVIDER_AUTH` | `true` | No | Tells TFC to use OIDC for AWS auth |
| `TFC_AWS_RUN_ROLE_ARN` | `arn:aws:iam::721559935914:role/terraform-cloud-deploy-role` | No | Which role to assume |

And under **Variables → Terraform variables** (these map to `variable {}` blocks in HCL):

| Key | Value | HCL checkbox |
|-----|-------|-------------|
| `aws_region` | `us-east-1` | **Unchecked** (plain string) |
| `environment` | `dev` (dev workspace) or `""` (prod workspace) | **Unchecked** (plain string) |

> **Important:** The HCL checkbox must be unchecked for plain string values. If checked, TFC writes `aws_region = us-east-1` (no quotes) which is invalid HCL.

---

## TFC API token — for GitHub Actions

GitHub Actions needs a TFC API token to authenticate the Terraform CLI to TFC. This is a **User token**:

- Go to [app.terraform.io](https://app.terraform.io) → avatar → **User settings** → **Tokens**
- Create token named `github-actions`, no expiry (rotate manually for production)
- Store as GitHub Actions secret `TFC_API_TOKEN` on the terraform repo

### Token types explained

| Type | Tied to | Can trigger runs | Use for |
|------|---------|-----------------|---------|
| User token | Your account | Yes | Personal projects, learning |
| Team token | A team | Yes | Production CI/CD (not person-dependent) |
| Organization token | Org | No (read-only) | Workspace/settings management |
| Audit token | Org audit stream | No | Compliance logging |

### Security best practice for secrets

Never paste tokens in chat or commit them to git. The safe pattern:
1. Set the token in your own terminal: `$env:TFC_TOKEN = "..."`
2. Run the secret-setting command yourself: `gh secret set TFC_API_TOKEN --body $env:TFC_TOKEN --repo ranjanumesh11/nyc-taxi-glue-terraform`
3. The value flows from memory → GitHub → never visible in logs or chat

---

## Verifying the workspace is ready

After a successful Terraform apply, you should see in the TFC workspace:
- **Runs** tab: a green completed apply
- **States** tab: current state with S3 buckets and Glue job
- **Resources** tab: all created resources listed

Expected resources after first apply:
- `aws_s3_bucket.glue_scripts`
- `aws_s3_bucket.raw_data`
- `aws_s3_bucket_versioning.glue_scripts`
- `aws_s3_bucket_versioning.raw_data`
- `aws_s3_bucket_public_access_block.glue_scripts`
- `aws_s3_bucket_public_access_block.raw_data`
- `aws_iam_role.glue_execution`
- `aws_iam_role_policy.glue_s3`
- `aws_iam_role_policy_attachment.glue_service`
- `module.yellow_taxi_april_2026_download.aws_glue_job.this`
