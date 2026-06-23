# Role assumed by the Glue service when running any job in this environment.
# Trust relationship: only glue.amazonaws.com can assume this role.
resource "aws_iam_role" "glue_execution" {
  name = "nyc-taxi-glue-execution-role${local.env_suffix}"
  tags = local.common_tags

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect    = "Allow"
        Principal = { Service = "glue.amazonaws.com" }
        Action    = "sts:AssumeRole"
      }
    ]
  })
}

# Minimum S3 permissions: read scripts, write raw data output.
resource "aws_iam_role_policy" "glue_s3" {
  name = "glue-s3-access"
  role = aws_iam_role.glue_execution.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "ReadScripts"
        Effect = "Allow"
        Action = ["s3:GetObject", "s3:ListBucket"]
        Resource = [
          aws_s3_bucket.glue_scripts.arn,
          "${aws_s3_bucket.glue_scripts.arn}/*"
        ]
      },
      {
        Sid    = "WriteRawData"
        Effect = "Allow"
        Action = ["s3:PutObject", "s3:GetObject", "s3:ListBucket"]
        Resource = [
          aws_s3_bucket.raw_data.arn,
          "${aws_s3_bucket.raw_data.arn}/*"
        ]
      }
    ]
  })
}

# AWS managed policy that allows Glue to write logs to CloudWatch.
resource "aws_iam_role_policy_attachment" "glue_service" {
  role       = aws_iam_role.glue_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSGlueServiceRole"
}
