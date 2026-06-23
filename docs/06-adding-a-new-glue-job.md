# Adding a New Glue Job

Every new Glue job follows the same two-step pattern: add the script to the app repo, add an infrastructure block to the terraform repo.

---

## Step 1 — Add the Python script (app repo: nyc-taxi-glue)

Create a new `.py` file under `scripts/`:

```
scripts/
  yellow_taxi/
    download_yellow_taxi_april_2026.py   ← existing
  green_taxi/
    download_green_taxi_april_2026.py    ← new job
```

Script structure (use `argparse` so it works both locally and inside Glue):

```python
import argparse
import boto3
import urllib.request
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

DATA_URL = "https://d37ci6vzurychx.cloudfront.net/trip-data/green_tripdata_2026-04.parquet"
FILENAME = "green_tripdata_2026-04.parquet"

parser = argparse.ArgumentParser()
parser.add_argument("--output_bucket", required=True)
parser.add_argument("--output_prefix", default="green/2026/04")
# parse_known_args ignores --JOB_NAME and other args Glue injects automatically
args, _ = parser.parse_known_args()

urllib.request.urlretrieve(DATA_URL, f"/tmp/{FILENAME}")
boto3.client("s3").upload_file(f"/tmp/{FILENAME}", args.output_bucket, f"{args.output_prefix}/{FILENAME}")
logger.info(f"Done — s3://{args.output_bucket}/{args.output_prefix}/{FILENAME}")
```

Commit and push to a feature branch, open a PR to `dev`. When merged, GitHub Actions uploads the script to:
```
s3://nyc-taxi-glue-scripts-721559935914-dev/scripts/green_taxi/download_green_taxi_april_2026.py
```

---

## Step 2 — Add the Glue job definition (this repo: nyc-taxi-glue-terraform)

In `main.tf` at the repo root, add a new `module` block. **Do not change the module itself.**

```hcl
module "green_taxi_april_2026_download" {
  source = "./modules/glue_job"

  job_name    = "green-taxi-april-2026-download${local.env_suffix}"
  description = "Downloads NYC green taxi April 2026 parquet to S3"
  role_arn    = aws_iam_role.glue_execution.arn
  script_location = "s3://${aws_s3_bucket.glue_scripts.bucket}/scripts/green_taxi/download_green_taxi_april_2026.py"

  default_arguments = {
    "--output_bucket" = aws_s3_bucket.raw_data.bucket
    "--output_prefix" = "green/2026/04"
  }

  tags = local.common_tags
}
```

Note `${local.env_suffix}` — this appends `-dev` on dev and nothing on prod automatically.

Commit and push to a feature branch, open a PR to `dev`. When merged, GitHub Actions triggers Terraform Cloud which creates the Glue job in AWS.

---

## Step 3 — Verify in dev, then promote to prod

After both PRs merge to `dev`:

```powershell
# Trigger the Glue job in dev
aws glue start-job-run `
  --job-name "green-taxi-april-2026-download-dev" `
  --profile default

# Monitor progress
aws glue get-job-runs `
  --job-name "green-taxi-april-2026-download-dev" `
  --profile default `
  --query "JobRuns[0].{State:JobRunState,Duration:ExecutionTime,Error:ErrorMessage}"

# Verify output landed in S3
aws s3 ls s3://nyc-taxi-raw-data-721559935914-dev/green/2026/04/ --profile default
```

Once verified, open PR `dev → main` on both repos. Merging creates prod resources (no `-dev` suffix).

---

## Naming conventions

| Resource | Pattern | Dev example | Prod example |
|----------|---------|-------------|--------------|
| Glue job | `<dataset>-<period>-<action><env_suffix>` | `yellow-taxi-april-2026-download-dev` | `yellow-taxi-april-2026-download` |
| Scripts bucket | `nyc-taxi-glue-scripts-<account><env_suffix>` | `nyc-taxi-glue-scripts-721559935914-dev` | `nyc-taxi-glue-scripts-721559935914` |
| Data bucket | `nyc-taxi-raw-data-<account><env_suffix>` | `nyc-taxi-raw-data-721559935914-dev` | `nyc-taxi-raw-data-721559935914` |
| Glue execution role | `nyc-taxi-glue-execution-role<env_suffix>` | `nyc-taxi-glue-execution-role-dev` | `nyc-taxi-glue-execution-role` |
| Script S3 path | `scripts/<dataset>/<filename>.py` | `scripts/yellow_taxi/download_yellow_taxi_april_2026.py` | same |

`env_suffix` = `-dev` when `var.environment = "dev"`, empty string when `var.environment = ""`.

---

## Summary checklist for every new job

- [ ] Script added under `scripts/<dataset>/` in app repo (`nyc-taxi-glue`)
- [ ] Script pushed to feature branch, PR to `dev`, merged → script lands in dev S3
- [ ] Module block added to root `main.tf` in terraform repo (`nyc-taxi-glue-terraform`)
- [ ] Terraform pushed to feature branch, PR to `dev`, merged → TFC creates dev Glue job
- [ ] Job triggered manually and verified (`aws glue get-job-runs ...`)
- [ ] Output data verified in dev raw data bucket (`aws s3 ls ...`)
- [ ] PR `dev → main` on both repos → prod deployment
