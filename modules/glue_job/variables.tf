variable "job_name" {
  type        = string
  description = "Unique name of the Glue job"
}

variable "description" {
  type        = string
  default     = ""
  description = "Human-readable job description"
}

variable "role_arn" {
  type        = string
  description = "IAM role ARN the job assumes at runtime (needs S3 read on scripts, S3 write on output)"
}

variable "script_location" {
  type        = string
  description = "S3 URI of the Python script, e.g. s3://my-bucket/scripts/job.py"
}

variable "glue_version" {
  type        = string
  default     = "4.0"
  description = "AWS Glue version. 4.0 supports Python 3.10 for Python Shell jobs."
}

variable "max_capacity" {
  type        = number
  default     = 0.0625
  description = "DPU allocation for Python Shell: 0.0625 (1/16 DPU, cheapest) or 1"
}

variable "max_retries" {
  type        = number
  default     = 0
}

variable "timeout" {
  type        = number
  default     = 60
  description = "Job timeout in minutes"
}

variable "default_arguments" {
  type        = map(string)
  default     = {}
  description = "Passed to the script as --key value CLI arguments"
}

variable "tags" {
  type    = map(string)
  default = {}
}
