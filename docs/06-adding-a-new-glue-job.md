# Adding a New Glue Job

---

## Where the interpreter is controlled

The `command.name` field inside `modules/glue_job/main.tf` (or `modules/glue_job_comprehensive/main.tf`) controls which execution engine AWS uses:

| `command.name` | Engine | Use case | Compute setting |
|----------------|--------|----------|-----------------|
| `"pythonshell"` | Plain Python on a single node | HTTP downloads, S3 copies, API calls, lightweight transforms | `max_capacity` (0.0625 or 1 DPU) |
| `"glueetl"` | Apache Spark (PySpark / Scala) | Large-scale distributed ETL, joins, aggregations across GBs–TBs | `number_of_workers` + `worker_type` |
| `"gluestreaming"` | Spark Structured Streaming | Continuous ingestion from Kinesis or Kafka | `number_of_workers` + `worker_type`, `timeout = null` |

In the **lean module** (`modules/glue_job/`), `command.name` is hardcoded to `"pythonshell"`. To create Spark or Streaming jobs, either:
- Use the **comprehensive module** (`modules/glue_job_comprehensive/`) which exposes `job_type` as a variable, or
- Add a separate `aws_glue_job` resource directly in `main.tf` without using the module

---

## Two main.tf files — what each one is for

| File | Purpose |
|------|---------|
| `main.tf` (repo root) | **What jobs exist** — one `module` block per Glue job. Edit this to add jobs. |
| `modules/glue_job/main.tf` | **How a job is built** — the `aws_glue_job` resource template. Rarely edited. |

Never put job-specific settings inside `modules/glue_job/main.tf`. That file is the template; `main.tf` at root is where you configure each job.

---

## Available arguments (lean module)

The current `modules/glue_job/` module exposes these variables:

| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| `job_name` | ✅ | — | Unique job name (include `${local.env_suffix}`) |
| `script_location` | ✅ | — | S3 URI to the .py script |
| `role_arn` | ✅ | — | IAM role the job assumes |
| `description` | No | `""` | Human-readable description |
| `glue_version` | No | `"4.0"` | AWS Glue version |
| `max_capacity` | No | `0.0625` | DPU for Python Shell (0.0625 or 1) |
| `max_retries` | No | `0` | Auto-retry count on failure |
| `timeout` | No | `60` | Kill job after N minutes |
| `default_arguments` | No | `{}` | `--key = "value"` args sent to the script |
| `tags` | No | `{}` | AWS resource tags |

---

## Job definition examples

### Example 1 — Simple Python Shell (baseline, what we use today)

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

The Python script receives `--output_bucket` and `--output_prefix` via `argparse`. Runs at 0.0625 DPU (cheapest). Killed after 60 minutes.

---

### Example 2 — Python Shell with higher compute, retries, and multiple arguments

Use when the script needs more memory (e.g. loading a large file into pandas) or must handle transient failures.

```hcl
module "yellow_taxi_monthly_profiler" {
  source = "./modules/glue_job"

  job_name        = "yellow-taxi-monthly-profiler${local.env_suffix}"
  description     = "Profiles yellow taxi monthly data: row counts, nulls, schema drift detection"
  role_arn        = aws_iam_role.glue_execution.arn
  script_location = "s3://${aws_s3_bucket.glue_scripts.bucket}/scripts/yellow_taxi/profile_monthly.py"

  glue_version = "4.0"
  max_capacity = 1        # full 1 DPU — 4× memory vs 0.0625
  max_retries  = 2        # retry twice on transient failures
  timeout      = 120      # allow up to 2 hours

  default_arguments = {
    "--input_bucket"   = aws_s3_bucket.raw_data.bucket
    "--input_prefix"   = "yellow/2026"
    "--output_bucket"  = aws_s3_bucket.raw_data.bucket
    "--output_prefix"  = "profiling/yellow/2026"
    "--year"           = "2026"
    "--months"         = "01,02,03,04"           # comma-separated, parsed in the script
    "--fail_on_drift"  = "true"
    "--notify_sns_arn" = "arn:aws:sns:us-east-1:721559935914:glue-alerts"
  }

  tags = merge(local.common_tags, {
    DataDomain = "yellow-taxi"
    JobClass   = "profiling"
  })
}
```

The script reads `--months` as a comma-separated string and loops. Multiple tags can be merged with `local.common_tags`.

---

### Example 3 — Spark ETL job (glueetl) using the comprehensive module

Switch to `modules/glue_job_comprehensive` for any non-Python-Shell job.

```hcl
module "yellow_taxi_spark_transform" {
  source = "./modules/glue_job_comprehensive"

  job_name        = "yellow-taxi-spark-transform${local.env_suffix}"
  description     = "PySpark job: cleans, casts types, partitions yellow taxi data by pickup date"
  role_arn        = aws_iam_role.glue_execution.arn
  script_location = "s3://${aws_s3_bucket.glue_scripts.bucket}/scripts/yellow_taxi/spark_transform.py"

  # ── Interpreter: Spark ──────────────────────────────────────────────────
  job_type       = "glueetl"     # Apache Spark — not Python Shell
  python_version = "3"           # PySpark; use "scala" entry point for Scala
  glue_version   = "4.0"

  # ── Compute ─────────────────────────────────────────────────────────────
  number_of_workers = 10         # 10 G.1X workers
  worker_type       = "G.1X"    # 4 vCPU, 16 GB RAM each
  execution_class   = "FLEX"    # Spot-backed workers — ~35% cheaper
                                 # only use FLEX when start-time doesn't matter

  # ── Execution control ────────────────────────────────────────────────────
  max_retries         = 1
  timeout             = 240      # 4 hours
  max_concurrent_runs = 3        # allow 3 parallel runs with different date args

  # ── Arguments passed to the PySpark script ──────────────────────────────
  default_arguments = {
    "--input_bucket"             = aws_s3_bucket.raw_data.bucket
    "--input_prefix"             = "yellow/2026/04"
    "--output_bucket"            = aws_s3_bucket.raw_data.bucket
    "--output_prefix"            = "yellow_clean/2026/04"
    "--partition_col"            = "pickup_date"

    # Spark UI — enables flame graphs and stage timelines in S3
    "--enable-spark-ui"          = "true"
    "--spark-event-logs-path"    = "s3://${aws_s3_bucket.raw_data.bucket}/spark-logs/"

    # Continuous CloudWatch logging — tail logs without waiting for job end
    "--enable-continuous-cloudwatch-log" = "true"
    "--continuous-log-logGroup"  = "/aws-glue/jobs/yellow-taxi-spark-transform"

    # Job bookmarks — skip already-processed files on re-run
    "--job-bookmark-option"      = "job-bookmark-enable"
  }

  # Lock down the output bucket so callers can't redirect output at runtime
  non_overridable_arguments = {
    "--output_bucket" = aws_s3_bucket.raw_data.bucket
  }

  tags = merge(local.common_tags, {
    DataDomain = "yellow-taxi"
    JobClass   = "transform"
    Engine     = "spark"
  })
}
```

---

### Example 4 — Spark ETL with JDBC connection (reading from RDS)

When a job reads from a database, it needs a Glue Connection for VPC access and credentials.

```hcl
module "rds_to_s3_extract" {
  source = "./modules/glue_job_comprehensive"

  job_name        = "rds-taxi-trips-extract${local.env_suffix}"
  description     = "Extracts trip records from RDS PostgreSQL to S3 parquet"
  role_arn        = aws_iam_role.glue_execution.arn
  script_location = "s3://${aws_s3_bucket.glue_scripts.bucket}/scripts/rds/extract_trips.py"

  job_type          = "glueetl"
  glue_version      = "4.0"
  number_of_workers = 5
  worker_type       = "G.1X"
  execution_class   = "STANDARD"   # STANDARD for JDBC — VPC init can be slow

  # Glue Connection provides VPC routing + secret credentials for the DB
  connections = [
    "rds-postgres-taxi-connection"   # created separately in Glue → Connections
  ]

  # Encrypt CloudWatch logs and job bookmarks with KMS
  security_configuration = "glue-kms-sec-config"

  timeout     = 90
  max_retries = 1

  # Delay alert: send EventBridge event if job is still running after 60 min
  notify_delay_after = 60

  default_arguments = {
    "--db_table"                         = "public.trip_records"
    "--output_bucket"                    = aws_s3_bucket.raw_data.bucket
    "--output_prefix"                    = "rds/trips"
    "--job-bookmark-option"              = "job-bookmark-enable"
    "--enable-continuous-cloudwatch-log" = "true"
    "--continuous-log-logGroup"          = "/aws-glue/jobs/rds-extract"
  }

  # Prevent callers from pointing at a different table
  non_overridable_arguments = {
    "--db_table" = "public.trip_records"
  }

  tags = merge(local.common_tags, {
    DataSource = "rds-postgres"
    JobClass   = "extract"
  })
}
```

---

### Example 5 — Spark Streaming job (Kinesis → S3)

```hcl
module "taxi_trips_kinesis_ingest" {
  source = "./modules/glue_job_comprehensive"

  job_name        = "taxi-trips-kinesis-ingest${local.env_suffix}"
  description     = "Continuously reads taxi trip events from Kinesis and lands them in S3"
  role_arn        = aws_iam_role.glue_execution.arn
  script_location = "s3://${aws_s3_bucket.glue_scripts.bucket}/scripts/streaming/kinesis_to_s3.py"

  job_type          = "gluestreaming"   # Spark Structured Streaming
  glue_version      = "4.0"
  number_of_workers = 4
  worker_type       = "G.1X"

  timeout             = null   # streaming jobs run indefinitely — no timeout
  max_concurrent_runs = 1      # only one streaming job per stream
  max_retries         = 0      # don't auto-retry streaming; investigate manually

  default_arguments = {
    "--kinesis_stream_arn"   = "arn:aws:kinesis:us-east-1:721559935914:stream/taxi-trips"
    "--output_bucket"        = aws_s3_bucket.raw_data.bucket
    "--output_prefix"        = "streaming/taxi-trips"
    "--checkpoint_location"  = "s3://${aws_s3_bucket.raw_data.bucket}/checkpoints/taxi-trips/"
    "--window_size"          = "100 seconds"

    "--enable-continuous-cloudwatch-log" = "true"
    "--continuous-log-logGroup"          = "/aws-glue/jobs/kinesis-ingest"
  }

  tags = merge(local.common_tags, {
    JobClass   = "streaming"
    DataSource = "kinesis"
  })
}
```

---

## default_arguments reference — commonly used keys

These are passed as `--key = "value"` in `default_arguments` and read by the script or by Glue itself.

### Script arguments (your own keys)

```hcl
default_arguments = {
  "--input_bucket"  = "my-source-bucket"
  "--output_prefix" = "yellow/2026/04"
  "--year"          = "2026"
  "--dry_run"       = "false"
}
```

Anything starting with `--` that Glue doesn't recognise is forwarded to the script as a CLI argument. Your script reads them with `argparse`.

### Glue system arguments (recognised by Glue itself)

| Key | Value | Effect |
|-----|-------|--------|
| `--job-bookmark-option` | `"job-bookmark-enable"` | Skip already-processed S3 files on re-run |
| `--job-bookmark-option` | `"job-bookmark-disable"` | Process all files every run (default) |
| `--enable-metrics` | `""` | Send Glue job metrics to CloudWatch |
| `--enable-job-insights` | `"true"` | Enable Glue Job Insights (anomaly detection) |
| `--enable-continuous-cloudwatch-log` | `"true"` | Stream logs to CloudWatch in real time (don't wait for job end) |
| `--continuous-log-logGroup` | `"/aws-glue/jobs/my-job"` | CloudWatch log group name |
| `--enable-spark-ui` | `"true"` | Enable Spark UI with stage/task details (Spark only) |
| `--spark-event-logs-path` | `"s3://my-bucket/spark-logs/"` | Where Spark UI stores event logs |
| `--TempDir` | `"s3://my-bucket/tmp/"` | Temp directory for Glue shuffle data |
| `--extra-py-files` | `"s3://my-bucket/libs/mylib.zip"` | Additional Python libraries to load |
| `--extra-jars` | `"s3://my-bucket/jars/connector.jar"` | Additional JARs for JDBC connectors |
| `--enable-glue-datacatalog` | `""` | Use Glue Data Catalog as Hive metastore |

---

## Step-by-step: adding a new job end to end

### Step 1 — Python script (app repo: nyc-taxi-glue)

```python
# scripts/green_taxi/download_green_taxi_april_2026.py
import argparse, boto3, urllib.request, logging

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
logger = logging.getLogger(__name__)

DATA_URL = "https://d37ci6vzurychx.cloudfront.net/trip-data/green_tripdata_2026-04.parquet"
FILENAME = "green_tripdata_2026-04.parquet"

parser = argparse.ArgumentParser()
parser.add_argument("--output_bucket", required=True)
parser.add_argument("--output_prefix", default="green/2026/04")
# parse_known_args discards --JOB_NAME and other args Glue injects automatically
args, _ = parser.parse_known_args()

logger.info(f"Downloading {DATA_URL}")
urllib.request.urlretrieve(DATA_URL, f"/tmp/{FILENAME}")
boto3.client("s3").upload_file(f"/tmp/{FILENAME}", args.output_bucket,
                               f"{args.output_prefix}/{FILENAME}")
logger.info(f"Done — s3://{args.output_bucket}/{args.output_prefix}/{FILENAME}")
```

Commit to a feature branch → PR to `dev` → merge → GitHub Actions uploads to dev S3.

### Step 2 — Job definition (this repo: root main.tf)

Add a new `module` block to `main.tf` at the repo root. Do not touch `modules/glue_job/`.

```hcl
module "green_taxi_april_2026_download" {
  source = "./modules/glue_job"

  job_name        = "green-taxi-april-2026-download${local.env_suffix}"
  description     = "Downloads NYC green taxi April 2026 parquet from TLC to S3"
  role_arn        = aws_iam_role.glue_execution.arn
  script_location = "s3://${aws_s3_bucket.glue_scripts.bucket}/scripts/green_taxi/download_green_taxi_april_2026.py"

  default_arguments = {
    "--output_bucket" = aws_s3_bucket.raw_data.bucket
    "--output_prefix" = "green/2026/04"
  }

  tags = local.common_tags
}
```

Commit to feature branch → PR to `dev` → merge → TFC creates `green-taxi-april-2026-download-dev` in AWS.

### Step 3 — Verify and promote

```powershell
# Trigger manually
aws glue start-job-run --job-name "green-taxi-april-2026-download-dev" --profile default

# Monitor (repeat until SUCCEEDED)
aws glue get-job-runs --job-name "green-taxi-april-2026-download-dev" --profile default `
  --query "JobRuns[0].{State:JobRunState,Duration:ExecutionTime,Error:ErrorMessage}"

# Confirm output in S3
aws s3 ls s3://nyc-taxi-raw-data-721559935914-dev/green/2026/04/ --profile default
```

Once verified → PR `dev → main` on both repos → prod resources created without `-dev` suffix.

---

## Naming conventions

| Resource | Pattern | Dev | Prod |
|----------|---------|-----|------|
| Glue job | `<dataset>-<period>-<action>${env_suffix}` | `yellow-taxi-april-2026-download-dev` | `yellow-taxi-april-2026-download` |
| Scripts bucket | `nyc-taxi-glue-scripts-<account>${env_suffix}` | `nyc-taxi-glue-scripts-721559935914-dev` | `nyc-taxi-glue-scripts-721559935914` |
| Data bucket | `nyc-taxi-raw-data-<account>${env_suffix}` | `nyc-taxi-raw-data-721559935914-dev` | `nyc-taxi-raw-data-721559935914` |
| Execution role | `nyc-taxi-glue-execution-role${env_suffix}` | `nyc-taxi-glue-execution-role-dev` | `nyc-taxi-glue-execution-role` |

`env_suffix` is defined in `s3.tf`: `var.environment != "" ? "-${var.environment}" : ""`

---

## The comprehensive module

`modules/glue_job_comprehensive/` is a reference-quality module covering every `aws_glue_job` argument. It is **not wired into main.tf** — it exists to be consulted or copied.

To use it for a new job requiring Spark/Streaming/connections:

1. Copy the `module` block from one of the examples above
2. Change `source = "./modules/glue_job"` → `source = "./modules/glue_job_comprehensive"`
3. Set `job_type`, `number_of_workers`, `worker_type` (and clear `max_capacity`)
4. Add the block to `main.tf` at the repo root

Or, to upgrade the lean module itself, copy `modules/glue_job_comprehensive/` over `modules/glue_job/` — all existing `module` blocks in `main.tf` will continue to work because the comprehensive module is a superset (all lean module variables still exist with the same names and defaults).

---

## Checklist for every new job

- [ ] Script added under `scripts/<dataset>/` in the app repo
- [ ] Feature branch → PR to `dev` → merged (script uploaded to dev S3)
- [ ] Module block added to root `main.tf` in this repo
- [ ] Feature branch → PR to `dev` → merged (TFC creates dev Glue job)
- [ ] Job triggered manually and reached `SUCCEEDED` state
- [ ] Output data verified in dev raw data bucket
- [ ] PR `dev → main` on both repos (creates prod resources)
