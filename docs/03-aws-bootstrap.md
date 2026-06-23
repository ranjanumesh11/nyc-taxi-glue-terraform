# AWS Bootstrap — One-Time Setup

These steps were run **once** to create the foundational IAM resources. Terraform cannot create these itself because they are the credentials Terraform needs to run.

## AWS account details

| Item | Value |
|------|-------|
| Account ID | `721559935914` |
| Region | `us-east-1` |
| IAM Identity Center portal | `https://ssoins-7223feb6e88fa100.portal.us-east-1.app.aws` |

---

## Step 1 — OIDC Identity Providers

OIDC providers allow external systems (GitHub, Terraform Cloud) to exchange their own short-lived JWTs for AWS temporary credentials — **no stored access keys needed anywhere**.

### GitHub Actions OIDC provider
Already existed in the account.
```
arn:aws:iam::721559935914:oidc-provider/token.actions.githubusercontent.com
```

### Terraform Cloud OIDC provider
Created with:
```powershell
aws iam create-open-id-connect-provider `
  --url https://app.terraform.io `
  --client-id-list aws.workload.identity `
  --thumbprint-list 9e99a48a9960b14926bb7f3b02e22da2b0ab7280 `
  --profile default
```
Result: `arn:aws:iam::721559935914:oidc-provider/app.terraform.io`

---

## Step 2 — IAM Roles

### Role 1: github-glue-script-deploy-role

**Purpose:** Used by GitHub Actions in `nyc-taxi-glue` (the app repo) to upload Python scripts to S3.

**Trust policy** (`iam/bootstrap/github-oidc-trust-policy.json`):
- Allows `token.actions.githubusercontent.com` to assume this role
- Scoped to any branch (`ref:refs/heads/*`) of `ranjanumesh11/nyc-taxi-glue` — covers both `dev` and `main` deploys

**Permissions** (`iam/bootstrap/github-deploy-permissions.json`):
- `s3:PutObject`, `s3:GetObject`, `s3:DeleteObject`, `s3:ListBucket`
- On both `nyc-taxi-glue-scripts-721559935914-dev` (dev) and `nyc-taxi-glue-scripts-721559935914` (prod) buckets

Created with:
```powershell
aws iam create-role `
  --role-name github-glue-script-deploy-role `
  --assume-role-policy-document "file://iam/bootstrap/github-oidc-trust-policy.json" `
  --profile default

aws iam put-role-policy `
  --role-name github-glue-script-deploy-role `
  --policy-name glue-script-s3-upload `
  --policy-document "file://iam/bootstrap/github-deploy-permissions.json" `
  --profile default
```

---

### Role 2: terraform-cloud-deploy-role

**Purpose:** Used by Terraform Cloud to create and manage AWS resources (S3 buckets, Glue jobs, IAM roles).

**Trust policy** (`iam/bootstrap/tfc-oidc-trust-policy.json`):
- Allows `app.terraform.io` to assume this role via OIDC
- Scoped to any workspace matching `nyc-taxi-glue-*` in `demo-kt-101` org — covers both `nyc-taxi-glue-dev` and `nyc-taxi-glue-prod`

**Permissions** (`iam/bootstrap/tfc-deploy-permissions.json`):
- Full access to Glue, S3, CloudWatch Logs
- IAM permissions scoped to creating/managing Glue execution roles

Created with:
```powershell
aws iam create-role `
  --role-name terraform-cloud-deploy-role `
  --assume-role-policy-document "file://iam/bootstrap/tfc-oidc-trust-policy.json" `
  --profile default

aws iam put-role-policy `
  --role-name terraform-cloud-deploy-role `
  --policy-name glue-infra-deploy `
  --policy-document "file://iam/bootstrap/tfc-deploy-permissions.json" `
  --profile default
```

---

### Role 3: nyc-taxi-glue-execution-role-dev

**Purpose:** Used by AWS Glue when the job actually runs. Created and managed **by Terraform** (in `iam.tf` at repo root) — not manually.

**Trust policy:** `glue.amazonaws.com` can assume this role.

**Permissions:**
- Read from `nyc-taxi-glue-scripts-721559935914` (to fetch the script)
- Read/write to `nyc-taxi-raw-data-721559935914` (to write downloaded data)
- CloudWatch Logs via the `AWSGlueServiceRole` managed policy

---

## Verify all roles exist

```powershell
aws iam get-role --role-name github-glue-script-deploy-role --profile default --query Role.Arn
aws iam get-role --role-name terraform-cloud-deploy-role --profile default --query Role.Arn
aws iam get-role --role-name nyc-taxi-glue-execution-role-dev --profile default --query Role.Arn
```

The third role only appears after Terraform has run for the first time.

---

## Re-creating from scratch

All JSON policy files are stored in `iam/bootstrap/`. If roles need to be recreated:
1. Delete the existing role: `aws iam delete-role --role-name <name>`
2. Re-run the `create-role` and `put-role-policy` commands above
