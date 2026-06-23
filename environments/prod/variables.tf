variable "aws_region" {
  type        = string
  description = "AWS region. Set as a TFC workspace variable to avoid hardcoding."
}

variable "environment" {
  type        = string
  description = "Deployment environment (dev, staging, prod). Set as a TFC workspace variable."
}
