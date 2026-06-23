# GitHub Actions Flow

## Branch strategy

```
feature/* ──→ PR ──→ dev ──→ PR ──→ main
                     │               │
              plan only        plan only
              (review)         (review)
                     │               │
              merge → apply   merge → apply
              (dev AWS)        (prod AWS)
```

- Work on `feature/*` branches (or directly on `dev` for small changes)
- PR to `dev` → triggers `terraform plan` (preview, no changes made)
- Merge to `dev` → triggers `terraform apply` → changes deploy to **dev** AWS resources
- PR `dev → main` → triggers `terraform plan` on prod workspace (final review)
- Merge to `main` → triggers `terraform apply` → changes deploy to **prod** AWS resources

---

## Repo 1: nyc-taxi-glue (app repo)

**Workflow:** `.github/workflows/deploy-scripts.yml`

### Triggers

Fires when files under `scripts/` change on a push to `dev` or `main`. Also supports manual dispatch:
```yaml
on:
  push:
    branches: [main, dev]
    paths:
      - "scripts/**"
  workflow_dispatch:
    inputs:
      environment:
        type: choice
        options: [dev, prod]
```

The `paths` filter means the workflow **only runs when scripts actually change** — no accidental deploys from README edits or workflow changes.

### What it does
1. Checks out the repo
2. Resolves the target bucket: `dev` branch → `GLUE_SCRIPTS_BUCKET_DEV`, `main` branch → `GLUE_SCRIPTS_BUCKET_PROD`
3. Exchanges a GitHub OIDC token for temporary AWS credentials by assuming `github-glue-script-deploy-role`
4. Runs `aws s3 sync scripts/ s3://<bucket>/scripts/ --delete`
5. Lists uploaded files for verification

### How OIDC works here (no stored AWS keys)

```
GitHub Actions job starts
        │
        ▼
GitHub generates OIDC JWT for this job
(contains: repo name, branch ref, workflow name — signed by GitHub)
        │
        ▼
aws-actions/configure-aws-credentials action
sends JWT to AWS STS: AssumeRoleWithWebIdentity
  - Role: github-glue-script-deploy-role
  - Condition: must be ranjanumesh11/nyc-taxi-glue on any branch (ref:refs/heads/*)
        │
        ▼
AWS returns temporary credentials (valid ~1 hour)
        │
        ▼
Remaining steps run with those credentials
aws s3 sync uploads the scripts
```

### GitHub variables and secrets for this repo

| Name | Type | Value |
|------|------|-------|
| `AWS_ACCOUNT_ID` | Secret | `721559935914` |
| `AWS_REGION` | Variable | `us-east-1` |
| `GLUE_SCRIPTS_BUCKET_DEV` | Variable | `nyc-taxi-glue-scripts-721559935914-dev` |
| `GLUE_SCRIPTS_BUCKET_PROD` | Variable | `nyc-taxi-glue-scripts-721559935914` |

---

## Repo 2: nyc-taxi-glue-terraform

**Workflow:** `.github/workflows/terraform.yml`

### Triggers
```yaml
on:
  push:
    branches: [main, dev]   # plan + apply
  pull_request:
    branches: [main, dev]   # plan only
```

### Workspace selection

The workflow sets `TF_WORKSPACE` based on the target branch. `TF_WORKSPACE` tells the Terraform CLI which TFC workspace to connect to:

```bash
TARGET="${{ github.base_ref || github.ref_name }}"
if [ "$TARGET" = "main" ]; then
  TF_WORKSPACE=nyc-taxi-glue-prod   # prod workspace → no suffix on AWS resources
else
  TF_WORKSPACE=nyc-taxi-glue-dev    # dev workspace → -dev suffix on AWS resources
fi
```

### What it does

**On PR to dev or main:**
1. `terraform init` — connects to TFC, downloads providers
2. `terraform fmt -check` — fails if formatting is wrong
3. `terraform validate` — checks HCL syntax
4. `terraform plan` — TFC executes the plan and streams output back

**On merge to dev or main:**
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
  → TFC selects workspace based on TF_WORKSPACE env var
        │
        ▼
terraform plan / apply
  → command intent is sent to TFC
  → TFC executes in its own isolated environment
  → TFC uses OIDC to get temporary AWS credentials (1-hour STS tokens)
  → TFC runs the actual Terraform providers against AWS
  → output streams back to GitHub runner in real time
```

**The GitHub runner never touches AWS directly.** It only needs the TFC token. AWS credentials are obtained by TFC via OIDC — inside TFC's environment.

### Why running from repo root matters

TFC's CLI-driven workflow uploads the **working directory** to TFC. If you run `terraform` from `environments/dev/`, only that folder is uploaded — the `modules/` directory outside it is unreachable.

Running from repo root means the entire repo is uploaded: `modules/glue_job/` resolves correctly as `./modules/glue_job`.

### Secrets on this repo

| Secret | Value | Set by |
|--------|-------|--------|
| `TFC_API_TOKEN` | TFC User API token | User sets via `gh secret set` in their own terminal |

---

## Secrets security principle

Secrets are never typed into chat or written to files. The safe pattern:
1. User sets secret in their own terminal session: `$env:MY_SECRET = "..."`
2. User runs the `gh secret set` command themselves from that terminal
3. The value flows from memory → GitHub → never visible in logs or chat

To verify secrets are configured:
```powershell
gh secret list --repo ranjanumesh11/nyc-taxi-glue
gh secret list --repo ranjanumesh11/nyc-taxi-glue-terraform
```
