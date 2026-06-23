# ─────────────────────────────────────────────────────────────────────────────
# Comprehensive Glue Job Module — All Parameters
#
# This module exposes EVERY supported aws_glue_job argument.
# Copy into modules/glue_job/ (replacing the lean template) when you need
# features beyond simple Python Shell jobs.
#
# Quick reference — job_type vs compute settings:
#
#   job_type = "pythonshell"   → set max_capacity (0.0625 or 1)
#                                 do NOT set number_of_workers / worker_type
#   job_type = "glueetl"       → set number_of_workers + worker_type
#                                 do NOT set max_capacity
#   job_type = "gluestreaming" → set number_of_workers + worker_type
#                                 timeout should be null (runs indefinitely)
# ─────────────────────────────────────────────────────────────────────────────

# ── Identity ──────────────────────────────────────────────────────────────────

variable "job_name" {
  type        = string
  description = "Unique name of the Glue job."
}

variable "description" {
  type        = string
  default     = ""
  description = "Human-readable description shown in the AWS console."
}

variable "role_arn" {
  type        = string
  description = "IAM role ARN the job assumes at runtime."
}

# ── Job type & interpreter ────────────────────────────────────────────────────

variable "job_type" {
  type        = string
  default     = "pythonshell"
  description = <<-EOT
    Controls the interpreter and execution model:
      "pythonshell"   — Plain Python on a single node. Best for HTTP downloads,
                        lightweight transforms, API calls. Cost: 0.0625–1 DPU.
      "glueetl"       — Apache Spark (PySpark or Scala). Distributed processing
                        for large datasets. Cost: number_of_workers × worker_type DPU/hr.
      "gluestreaming" — Spark Structured Streaming. Continuously reads from
                        Kinesis/Kafka. Runs indefinitely (set timeout = null).
  EOT
  validation {
    condition     = contains(["pythonshell", "glueetl", "gluestreaming"], var.job_type)
    error_message = "job_type must be 'pythonshell', 'glueetl', or 'gluestreaming'."
  }
}

variable "python_version" {
  type        = string
  default     = "3.9"
  description = <<-EOT
    Python version string for the command block.
      "3.9"  — Python Shell only (recommended, latest)
      "3"    — Spark/Streaming PySpark jobs
      "2"    — Deprecated; avoid
  EOT
}

variable "glue_version" {
  type        = string
  default     = "4.0"
  description = <<-EOT
    AWS Glue version. Determines available Python, Spark, and worker types.
      "4.0"  — Python 3.10 (Shell), Spark 3.3, all G.x/R.x workers. Recommended.
      "3.0"  — Python 3.7 (Shell), Spark 3.1
      "2.0"  — Python 3.7 (Shell), Spark 2.4, 10x faster startup than 1.0
      "1.0"  — Legacy
  EOT
}

variable "script_location" {
  type        = string
  description = "S3 URI of the Python or Scala script. e.g. s3://my-bucket/scripts/job.py"
}

# ── Compute — Python Shell ────────────────────────────────────────────────────

variable "max_capacity" {
  type        = number
  default     = null
  description = <<-EOT
    DPU allocation for Python Shell jobs only.
      0.0625  (1/16 DPU) — Cheapest. ~$0.044/hr. Enough for most scripts.
      1       (1 DPU)    — 4× more memory/CPU. Use for memory-intensive tasks.
    Set null for Spark/Streaming jobs.
  EOT
}

# ── Compute — Spark / Streaming ───────────────────────────────────────────────

variable "number_of_workers" {
  type        = number
  default     = null
  description = <<-EOT
    Number of Spark workers. Required for glueetl and gluestreaming.
    Set null for Python Shell jobs.
    Minimum: 2.
  EOT
}

variable "worker_type" {
  type        = string
  default     = null
  description = <<-EOT
    Spark worker size. Required for glueetl and gluestreaming.
    Set null for Python Shell jobs.

      Standard  — 4 vCPU, 16 GB RAM, 50 GB disk.  Legacy. Prefer G.1X.
      G.025X    — 2 vCPU,  4 GB RAM, 64 GB disk.  Glue 3.0+ only.
      G.1X      — 4 vCPU, 16 GB RAM, 64 GB disk.  Recommended default.
      G.2X      — 8 vCPU, 32 GB RAM, 128 GB disk. Memory-heavy joins/aggregations.
      G.4X      — 16 vCPU, 64 GB RAM, 256 GB disk.
      G.8X      — 32 vCPU, 128 GB RAM, 512 GB disk.
      Z.2X      — 8 vCPU, 64 GB RAM (Ray jobs).
  EOT
}

variable "execution_class" {
  type        = string
  default     = "STANDARD"
  description = <<-EOT
    Spark only. Controls whether workers are On-Demand or Spot-backed.
      "STANDARD"  — On-Demand workers. Guaranteed capacity. Good for SLA-bound jobs.
      "FLEX"      — Spot + On-Demand mix. ~35% cheaper. May start slowly.
                    Not suitable for streaming or jobs with < 15 min runtime.
  EOT
  validation {
    condition     = contains(["STANDARD", "FLEX"], var.execution_class)
    error_message = "execution_class must be 'STANDARD' or 'FLEX'."
  }
}

# ── Execution control ─────────────────────────────────────────────────────────

variable "max_retries" {
  type        = number
  default     = 0
  description = "Number of automatic retries on failure. 0 = fail immediately."
}

variable "timeout" {
  type        = number
  default     = 60
  description = <<-EOT
    Job timeout in minutes. Job is killed if it runs longer.
    Set null for streaming jobs (they run indefinitely).
    AWS default if not set: 2880 min (48 hrs) for Shell/Spark, unlimited for Streaming.
  EOT
}

variable "max_concurrent_runs" {
  type        = number
  default     = 1
  description = "Maximum simultaneous runs of this job. Raise if you trigger it in parallel with different args."
}

variable "job_run_queuing_enabled" {
  type        = bool
  default     = false
  description = "When true, job runs that can't start immediately are queued rather than failed."
}

# ── Arguments ─────────────────────────────────────────────────────────────────

variable "default_arguments" {
  type        = map(string)
  default     = {}
  description = <<-EOT
    Arguments passed to the script (and overridable per run).
    Keys must start with "--". Values are strings.
    Merged on top of the module's built-in defaults (job-bookmark-disable, enable-metrics).
    Common keys — see docs/06-adding-a-new-glue-job.md for full reference.
  EOT
}

variable "non_overridable_arguments" {
  type        = map(string)
  default     = {}
  description = <<-EOT
    Arguments that CANNOT be overridden at run-time by start-job-run callers.
    Use to lock down security-sensitive settings (e.g. output bucket path).
    Same "--key" = "value" format as default_arguments.
  EOT
}

# ── Networking & security ─────────────────────────────────────────────────────

variable "connections" {
  type        = list(string)
  default     = []
  description = <<-EOT
    List of Glue Connection names to attach to this job.
    Required when the job reads from a JDBC source (RDS, Redshift, on-prem DB)
    or when it needs VPC network access.
  EOT
}

variable "security_configuration" {
  type        = string
  default     = null
  description = <<-EOT
    Name of a Glue Security Configuration.
    Use to enable encryption of: CloudWatch logs, job bookmarks, S3 data (SSE-KMS).
    Create the Security Configuration separately; reference it by name here.
  EOT
}

# ── Notifications ─────────────────────────────────────────────────────────────

variable "notify_delay_after" {
  type        = number
  default     = null
  description = <<-EOT
    Minutes to wait before sending a job delay notification via EventBridge.
    Set null to disable delay notifications.
    Useful for long-running jobs where you want an early warning if they're stuck.
  EOT
}

# ── Tags ──────────────────────────────────────────────────────────────────────

variable "tags" {
  type        = map(string)
  default     = {}
  description = "AWS resource tags applied to the Glue job."
}
