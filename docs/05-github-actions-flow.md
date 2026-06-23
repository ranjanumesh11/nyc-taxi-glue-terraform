# GitHub Actions Flow

## Branch strategy

```
dev  ──→ PR ──→ main
```

- All work happens on `dev` (or feature branches off `dev`)
- A PR from `dev` to `main` triggers a Terraform **plan** — you see exactly what will change
- Merging the PR to `main` triggers Terraform **apply** — changes deploy to AWS
- Direct pushes to `main` are discouraged; use PRs

---

## Repo 1: nyc-taxi-glue (app repo)

**Workflow:** `.github/workflows/deploy-scripts.yml`

### Trigger
Only fires when files under `scripts/` change on a push to `main`:
```yaml
on:
  push:
    branches: [main]
    paths:
      - "scripts/**"
```

### What it does
1. Checks out the repo
2. Exchanges a GitHub OIDC token for temporary AWS credentials by assuming `github-glue-script-deploy-role`
3. Runs `aws s3 sync scripts/ s3://nyc-taxi-glue-scripts-721559935914/scripts/`
4. Lists uploaded files for verification

### How OIDC works here (no stored AWS keys)
```
GitHub Actions job starts
        │
        ▼
GitHub generates OIDC JWT for this job
(contains: repo name, branch, workflow name)
        │
        ▼
aws-actions/configure-aws-credentials action
sends JWT to AWS STS: AssumeRoleWithWebIdentity
  - Role: github-glue-script-deploy-role
  - Condition: must be ranjanumesh11/nyc-taxi-glue on refs/heads/main
        │
        ▼
AWS returns temporary credentials (valid ~1 hour)
        │
        ▼
Remaining steps run with those credentials
aws s3 sync uploads the scripts
```

### Secrets on this repo

| Secret | Value | Set by |
|--------|-------|--------|
| `AWS_ACCOUNT_ID` | `721559935914` | `gh secret set` via CLI |
| `GLUE_SCRIPTS_BUCKET` | `nyc-taxi-glue-scripts-721559935914` | `gh secret set` via CLI |

---

## Repo 2: nyc-taxi-glue-terraform

**Workflow:** `.github/workflows/terraform.yml`

### Triggers
```yaml
on:
  push:
    branches: [main]      # runs plan + apply
  pull_request:
    branches: [main]      # runs plan only (no apply)
```

### What it does

**On PR to main:**
1. `terraform init` — connects to TFC, downloads providers
2. `terraform fmt -check` — fails if formatting is wrong
3. `terraform validate` — checks syntax
4. `terraform plan` — TFC executes the plan and streams output back

**On merge to main:**
All of the above, plus:
5. `terraform apply -auto-approve` — TFC executes the apply

### How the GitHub runner talks to Terraform Cloud
```
GitHub Actions runner
        │
        │  TFC_API_TOKEN secret
        ▼
hashicorp/setup-terraform action
configures ~/.terraform.d/credentials.tfrc.json
        │
        ▼
terraform init
  → CLI reads cloud {} block in terraform.tf
  → authenticates to TFC using the token
  → TFC creates a run
        │
        ▼
terraform plan / apply
  → commands are sent to TFC
  → TFC executes them in its own environment
  → TFC uses OIDC to get AWS credentials
  → output streams back to GitHub runner
```

The GitHub runner **does not need AWS credentials**. It only needs the TFC token. AWS credentials are obtained by TFC via OIDC.

### Secrets on this repo

| Secret | Value | Set by |
|--------|-------|--------|
| `TFC_API_TOKEN` | TFC User API token | Set by user in their own terminal |

---

## Secrets security principle

Secrets are never typed into chat or written to files. The pattern used throughout:
1. User sets secret in their own terminal session: `$env:MY_SECRET = "..."`
2. User runs the `gh secret set` command themselves from that terminal
3. The value flows from memory → GitHub → never visible in logs or chat

To verify secrets are configured:
```powershell
gh secret list --repo ranjanumesh11/nyc-taxi-glue
gh secret list --repo ranjanumesh11/nyc-taxi-glue-terraform
```
