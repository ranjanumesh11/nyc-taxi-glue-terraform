# Architecture — How Everything Connects

## The two repos and their responsibilities

| Repo | Responsibility | Deploys via |
|------|---------------|-------------|
| `nyc-taxi-glue` | Python Glue scripts (the actual job code) | GitHub Actions → S3 |
| `nyc-taxi-glue-terraform` | AWS infrastructure (Glue jobs, S3 buckets, IAM roles) | GitHub Actions → Terraform Cloud → AWS |

---

## End-to-end flow diagram

```
┌─────────────────────────────────────────────────────────────────────────────┐
│  Repo 1: nyc-taxi-glue (App)         Repo 2: nyc-taxi-glue-terraform        │
│                                                                               │
│  scripts/                             modules/glue_job/  ← module template  │
│    yellow_taxi/                       main.tf (repo root) ← job definitions │
│      download.py ─────────────────────→ script_location = s3://...          │
│                                                                               │
│  .github/workflows/                   .github/workflows/                     │
│    deploy-scripts.yml                   terraform.yml                        │
│         │                                    │                               │
│  [OIDC] │ exchanges GitHub JWT              │ TFC_API_TOKEN secret           │
│         ▼                                    ▼                               │
│    AWS STS                            Terraform Cloud                        │
│    assumes role:                            │                                │
│    github-glue-script-deploy-role    [OIDC] │ exchanges TFC JWT              │
│         │                                    ▼                               │
│         ▼                             AWS STS                                │
│    S3 (uploads .py file)              assumes role:                          │
│    nyc-taxi-glue-scripts-*            terraform-cloud-deploy-role            │
│                                             │                                │
│                                             ▼                                │
│                                       AWS creates/updates:                   │
│                                       - S3 buckets                           │
│                                       - Glue execution role                  │
│                                       - Glue job (points to S3 script)       │
└─────────────────────────────────────────────────────────────────────────────┘

                    When Glue job RUNS (triggered manually or on schedule):

                    AWS Glue service
                         │
                   assumes role:
                   nyc-taxi-glue-execution-role-dev
                         │
                         ├── reads script from S3 (nyc-taxi-glue-scripts-*)
                         ├── executes download_yellow_taxi_april_2026.py
                         └── writes parquet to S3 (nyc-taxi-raw-data-*)
```

---

## What is a Glue job — clearing the misconception

A Glue job is **not just a JSON file**. It has two distinct parts:

### Part 1 — Job definition (what Terraform manages)
An AWS resource that contains configuration:
- Which script to run (S3 path)
- Which IAM role to use
- Compute type and size (Python Shell vs Spark, DPU count)
- Timeout and retry settings
- Default arguments passed to the script

Terraform's `aws_glue_job` resource creates this. It is *represented* as JSON/HCL but it lives as an AWS API object.

### Part 2 — The script (what the app repo manages)
A Python `.py` file stored in S3. This is the actual business logic — what downloads, transforms, or loads data. Glue pulls this file from S3 at runtime and executes it.

**Terraform manages Part 1. The app repo manages Part 2. Both must exist for a job to run.**

---

## The three IAM roles

| Role name | Who assumes it | When | What it can do |
|-----------|---------------|------|----------------|
| `github-glue-script-deploy-role` | GitHub Actions (app repo) | On push to master | Upload `.py` files to the scripts S3 bucket |
| `terraform-cloud-deploy-role` | Terraform Cloud | On every plan/apply run | Create/update Glue jobs, S3 buckets, IAM roles |
| `nyc-taxi-glue-execution-role-dev` | AWS Glue service | When the job runs | Read scripts from S3, write output data to S3 |

Each role uses a **trust policy** that restricts exactly who can assume it:
- The GitHub role trusts only the `ranjanumesh11/nyc-taxi-glue` repo
- The TFC role trusts only the `nyc-taxi-glue-dev` workspace in the `demo-kt-101` org
- The Glue role trusts only `glue.amazonaws.com`

---

## The module pattern — one module, many jobs

There are **two** `main.tf` files in this repo — this is intentional:

| File | Purpose |
|------|---------|
| `main.tf` (repo root) | Declares which Glue jobs exist — one `module` block per job |
| `modules/glue_job/main.tf` | The module implementation — defines the `aws_glue_job` resource template |

The `modules/glue_job/` folder is a reusable template written once and never changed for individual jobs. To add a new Glue job, add a new `module` block in `main.tf` at the **repo root** — not inside `modules/`:

```hcl
# Existing job — in main.tf at repo root
module "yellow_taxi_april_2026_download" {
  source          = "./modules/glue_job"
  job_name        = "yellow-taxi-april-2026-download${local.env_suffix}"
  script_location = "s3://${aws_s3_bucket.glue_scripts.bucket}/scripts/yellow_taxi/download_yellow_taxi_april_2026.py"
  role_arn        = aws_iam_role.glue_execution.arn
  default_arguments = {
    "--output_bucket" = aws_s3_bucket.raw_data.bucket
    "--output_prefix" = "yellow/2026/04"
  }
  tags = local.common_tags
}

# Adding a new job — just a new block below, module unchanged
module "green_taxi_april_2026_download" {
  source          = "./modules/glue_job"
  job_name        = "green-taxi-april-2026-download${local.env_suffix}"
  script_location = "s3://${aws_s3_bucket.glue_scripts.bucket}/scripts/green_taxi/download_green_taxi_april_2026.py"
  role_arn        = aws_iam_role.glue_execution.arn
  default_arguments = {
    "--output_bucket" = aws_s3_bucket.raw_data.bucket
    "--output_prefix" = "green/2026/04"
  }
  tags = local.common_tags
}
```

The `source = "./modules/glue_job"` path resolves from repo root. Terraform Cloud uploads the entire repo root directory, so `modules/` is always reachable.

---

## S3 buckets — why we don't use the auto-created aws-glue-assets bucket

When you create a Glue job through the **AWS console**, AWS automatically provisions a bucket named `aws-glue-assets-<account-id>-<region>`. This is a convenience feature — AWS silently creates it and points the job's script location and temp storage there.

When creating Glue jobs through **Terraform** (or any API/CLI call), AWS does not automatically provision this bucket. Terraform creates exactly what you declare — no hidden side effects.

We explicitly defined our own S3 buckets:

| Bucket | Purpose |
|--------|---------|
| `nyc-taxi-glue-scripts-<account-id>[-dev]` | Stores Python scripts (.py files) |
| `nyc-taxi-raw-data-<account-id>[-dev]` | Stores downloaded parquet output |

This gives us full control over naming (predictable, environment-suffixed), lifecycle policies, access controls, and versioning — rather than relying on a bucket AWS auto-names and auto-configures with whatever defaults it chooses.

---

## Python Shell vs Spark (glueetl) jobs

The current setup uses **Python Shell** jobs. Here is the difference:

| | Python Shell | Glue ETL (Spark) |
|--|--|--|
| Use case | Simple downloads, API calls, lightweight transforms | Large-scale distributed data processing |
| Compute | 0.0625 DPU (1/16) or 1 DPU | 2+ workers (G.1X, G.2X) |
| Cost | ~$0.044/hour for 1/16 DPU | Much higher |
| Script type | Plain Python + boto3 | PySpark / Spark SQL |
| Terraform field | `max_capacity` | `number_of_workers` + `worker_type` |

For downloading NYC taxi data (a simple HTTP download + S3 upload), Python Shell is the right choice.
