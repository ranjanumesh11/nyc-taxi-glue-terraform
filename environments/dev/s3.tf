data "aws_caller_identity" "current" {}

locals {
  account_id      = data.aws_caller_identity.current.account_id
  scripts_bucket  = "nyc-taxi-glue-scripts-${local.account_id}"
  raw_data_bucket = "nyc-taxi-raw-data-${local.account_id}"
  common_tags = {
    Environment = var.environment
    Project     = "nyc-taxi"
    ManagedBy   = "terraform"
  }
}

# Holds the Python scripts uploaded by the app repo GitHub Actions.
resource "aws_s3_bucket" "glue_scripts" {
  bucket = local.scripts_bucket
  tags   = local.common_tags
}

resource "aws_s3_bucket_versioning" "glue_scripts" {
  bucket = aws_s3_bucket.glue_scripts.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_public_access_block" "glue_scripts" {
  bucket                  = aws_s3_bucket.glue_scripts.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Holds the raw parquet files the Glue job downloads.
resource "aws_s3_bucket" "raw_data" {
  bucket = local.raw_data_bucket
  tags   = local.common_tags
}

resource "aws_s3_bucket_versioning" "raw_data" {
  bucket = aws_s3_bucket.raw_data.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_public_access_block" "raw_data" {
  bucket                  = aws_s3_bucket.raw_data.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}
