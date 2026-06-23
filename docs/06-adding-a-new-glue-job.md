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

Script structure (use argparse so it works both locally and in Glue):

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
args, _ = parser.parse_known_args()

urllib.request.urlretrieve(DATA_URL, f"/tmp/{FILENAME}")
boto3.client("s3").upload_file(f"/tmp/{FILENAME}", args.output_bucket, f"{args.output_prefix}/{FILENAME}")
logger.info(f"Done — s3://{args.output_bucket}/{args.output_prefix}/{FILENAME}")
```

Commit and push to `dev`, then open a PR to `main`. When the PR merges, GitHub Actions uploads the script to:
```
s3://nyc-taxi-glue-scripts-721559935914-dev/scripts/green_taxi/download_green_taxi_april_2026.py
```

---

## Step 2 — Add the Glue job definition (this repo: nyc-taxi-glue-terraform)

In `environments/dev/main.tf`, add a new `module` block. **Do not change the module itself.**

```hcl
module "green_taxi_april_2026_download" {
  source = "../../modules/glue_job"

  job_name        = "green-taxi-april-2026-download-dev"
  description     = "Downloads NYC green taxi April 2026 parquet to S3"
  role_arn        = aws_iam_role.glue_execution.arn
  script_location = "s3://${aws_s3_bucket.glue_scripts.bucket}/scripts/green_taxi/download_green_taxi_april_2026.py"

  default_arguments = {
    "--output_bucket" = aws_s3_bucket.raw_data.bucket
    "--output_prefix" = "green/2026/04"
  }

  tags = local.common_tags
}
```

Commit and push to `dev`, then open a PR to `main`. When merged, GitHub Actions triggers Terraform Cloud which creates the Glue job in AWS.

---

## Step 3 — Run the job

Trigger manually from the AWS console or CLI:

```powershell
aws glue start-job-run `
  --job-name "green-taxi-april-2026-download-dev" `
  --arguments "--output_bucket=nyc-taxi-raw-data-721559935914-dev,--output_prefix=green/2026/04" `
  --profile default
```

Monitor the run:
```powershell
aws glue get-job-runs --job-name "green-taxi-april-2026-download-dev" --profile default
```

Check output in S3:
```powershell
aws s3 ls s3://nyc-taxi-raw-data-721559935914-dev/green/2026/04/ --profile default
```

---

## Naming conventions

| Resource | Pattern | Example |
|----------|---------|---------|
| Glue job | `<dataset>-<period>-<action>-<env>` | `yellow-taxi-april-2026-download-dev` |
| S3 scripts bucket | `nyc-taxi-glue-scripts-<account>-<env>` | `nyc-taxi-glue-scripts-721559935914-dev` |
| S3 data bucket | `nyc-taxi-raw-data-<account>-<env>` | `nyc-taxi-raw-data-721559935914-dev` |
| Glue execution role | `nyc-taxi-glue-execution-role-<env>` | `nyc-taxi-glue-execution-role-dev` |
| Script path in S3 | `scripts/<dataset>/<filename>.py` | `scripts/yellow_taxi/download_yellow_taxi_april_2026.py` |

Adding `<env>` as a suffix to all AWS resources means dev, staging, and prod can coexist in the same account without collisions.

---

## Summary checklist for every new job

- [ ] Script added to `scripts/<dataset>/` in app repo
- [ ] Script pushed to `dev`, PR opened to `main`, merged (auto-uploads to S3)
- [ ] Module block added to `environments/dev/main.tf` in terraform repo
- [ ] Terraform pushed to `dev`, PR opened to `main`, merged (TFC creates Glue job)
- [ ] Job triggered and verified via `aws glue get-job-runs`
- [ ] Output data verified in S3 raw data bucket
