# Each new Glue job = a new module block below. The module itself never changes.
# Add a green_taxi job? Copy this block, change job_name, script_location, and arguments.

module "yellow_taxi_april_2026_download" {
  source = "../../modules/glue_job"

  job_name        = "yellow-taxi-april-2026-download"
  description     = "Downloads NYC yellow taxi April 2026 parquet from the public TLC dataset to S3"
  role_arn        = aws_iam_role.glue_execution.arn
  script_location = "s3://${aws_s3_bucket.glue_scripts.bucket}/scripts/yellow_taxi/download_yellow_taxi_april_2026.py"

  default_arguments = {
    "--output_bucket" = aws_s3_bucket.raw_data.bucket
    "--output_prefix" = "yellow/2026/04"
  }

  tags = local.common_tags
}
