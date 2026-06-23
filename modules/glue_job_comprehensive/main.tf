resource "aws_glue_job" "this" {
  name        = var.job_name
  description = var.description
  role_arn    = var.role_arn

  glue_version = var.glue_version

  # ── Interpreter & script ──────────────────────────────────────────────────
  # job_type controls the execution model:
  #   "pythonshell"   → plain Python on a single node
  #   "glueetl"       → Apache Spark (PySpark / Scala)
  #   "gluestreaming" → Spark Structured Streaming
  command {
    name            = var.job_type
    script_location = var.script_location
    python_version  = var.python_version
  }

  # ── Compute ───────────────────────────────────────────────────────────────
  # Python Shell:  set max_capacity (0.0625 or 1), leave workers null
  # Spark/Stream:  set number_of_workers + worker_type, leave max_capacity null
  max_capacity      = var.job_type == "pythonshell" ? coalesce(var.max_capacity, 0.0625) : null
  number_of_workers = var.job_type != "pythonshell" ? var.number_of_workers : null
  worker_type       = var.job_type != "pythonshell" ? var.worker_type : null

  # FLEX execution class (Spot-backed, ~35% cheaper) — Spark only
  execution_class = var.job_type == "glueetl" ? var.execution_class : null

  # ── Execution control ─────────────────────────────────────────────────────
  max_retries             = var.max_retries
  timeout                 = var.timeout
  job_run_queuing_enabled = var.job_run_queuing_enabled

  execution_property {
    max_concurrent_runs = var.max_concurrent_runs
  }

  # ── Arguments ─────────────────────────────────────────────────────────────
  # Built-in defaults merged first; caller's default_arguments win on conflict.
  default_arguments = merge(
    {
      "--job-bookmark-option" = "job-bookmark-disable"
      "--enable-metrics"      = ""
      "--enable-job-insights" = "true"
    },
    var.default_arguments
  )

  non_overridable_arguments = length(var.non_overridable_arguments) > 0 ? var.non_overridable_arguments : null

  # ── Networking & security ─────────────────────────────────────────────────
  connections            = length(var.connections) > 0 ? var.connections : null
  security_configuration = var.security_configuration

  # ── Notifications ─────────────────────────────────────────────────────────
  dynamic "notification_property" {
    for_each = var.notify_delay_after != null ? [var.notify_delay_after] : []
    content {
      notify_delay_after = notification_property.value
    }
  }

  tags = var.tags
}
