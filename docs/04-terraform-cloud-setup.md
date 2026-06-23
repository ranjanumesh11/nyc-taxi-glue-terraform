# Terraform Cloud Setup

## Account and organization

| Item | Value |
|------|-------|
| Platform | [app.terraform.io](https://app.terraform.io) |
| Organization | `demo-kt-101` |
| Workspace | `nyc-taxi-glue-dev` |
| Workspace type | CLI-driven |

---

## Why Terraform Cloud

Terraform Cloud handles:
- Remote state storage (no S3 backend or local `.tfstate` files)
- Remote plan/apply execution (not on GitHub runner or your laptop)
- State locking (prevents two runs colliding)
- Run history and audit log

---

## Workspace: nyc-taxi-glue-dev

**Type: CLI-driven workflow**
This means GitHub Actions calls `terraform plan` / `terraform apply` using the Terraform CLI. The CLI is configured to talk to TFC via the `cloud {}` block in `environments/dev/terraform.tf`. The actual execution happens inside TFC — the GitHub runner just orchestrates.

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
  - Does sub match organization:demo-kt-101:project:*:workspace:nyc-taxi-glue-dev:run_phase:*? ✓
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

Set on the `nyc-taxi-glue-dev` workspace under **Variables → Environment variables**:

| Key | Value | Sensitive |
|-----|-------|-----------|
| `TFC_AWS_PROVIDER_AUTH` | `true` | No |
| `TFC_AWS_RUN_ROLE_ARN` | `arn:aws:iam::721559935914:role/terraform-cloud-deploy-role` | No |

These two variables are all that is needed. The AWS provider in `terraform.tf` has no credentials configured — TFC injects them automatically at runtime.

---

## TFC API token — for GitHub Actions

GitHub Actions needs a TFC API token to authenticate the Terraform CLI to TFC. This is a **User token** (not org/team/audit):

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

Never paste tokens in chat or commit them to git. When working with tools like Claude Code:
1. Set the token in your own terminal: `$env:TFC_TOKEN = "..."`
2. Run the secret-setting command yourself: `gh secret set TFC_API_TOKEN --body $env:TFC_TOKEN --repo ...`
3. The value never appears in chat or logs

---

## Verifying the workspace is ready

After a successful Terraform apply, you should see in the TFC workspace:
- **Runs** tab: a green completed apply
- **States** tab: current state with S3 buckets and Glue job
- **Resources** tab: all created resources listed
