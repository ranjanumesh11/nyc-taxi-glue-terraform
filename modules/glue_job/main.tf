resource "aws_glue_job" "this" {
  name         = var.job_name
  description  = var.description
  role_arn     = var.role_arn
  glue_version = var.glue_version

  # "pythonshell" runs the script as plain Python (no Spark).
  # Cheaper and faster for simple download/transform tasks.
  command {
    name            = "pythonshell"
    script_location = var.script_location
    python_version  = "3.9"
  }

  # max_capacity is used for Python Shell jobs (0.0625 or 1 DPU).
  # For Spark (glueetl) jobs you would use number_of_workers + worker_type instead.
  max_capacity = var.max_capacity
  max_retries  = var.max_retries
  timeout      = var.timeout

  default_arguments = merge(
    {
      "--job-bookmark-option" = "job-bookmark-disable"
    },
    var.default_arguments
  )

  tags = var.tags
}
