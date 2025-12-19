# S3 Bucket for error logging
resource "aws_s3_bucket" "firehose_error_logs" {
  bucket = "${var.project_name}-${var.environment}-firehose-errors"

  tags = {
    Name = "${var.project_name}-${var.environment}-firehose-errors"
  }
}

resource "aws_s3_bucket_versioning" "firehose_error_logs" {
  bucket = aws_s3_bucket.firehose_error_logs.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_public_access_block" "firehose_error_logs" {
  bucket = aws_s3_bucket.firehose_error_logs.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# CloudWatch Log Group for Firehose
resource "aws_cloudwatch_log_group" "firehose_logs" {
  count = var.enable_cloudwatch_logging ? 1 : 0

  name              = "/aws/kinesisfirehose/${var.project_name}-${var.environment}"
  retention_in_days = 7

  tags = {
    Name = "${var.project_name}-${var.environment}-firehose-logs"
  }
}

resource "aws_cloudwatch_log_stream" "firehose_logs" {
  count = var.enable_cloudwatch_logging ? 1 : 0

  name           = "S3TablesDelivery"
  log_group_name = aws_cloudwatch_log_group.firehose_logs[0].name
}

# IAM Role for Firehose
resource "aws_iam_role" "firehose_role" {
  name = "${var.project_name}-${var.environment}-firehose-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "firehose.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Name = "${var.project_name}-${var.environment}-firehose-role"
  }
}

# IAM Policy for Firehose
resource "aws_iam_role_policy" "firehose_policy" {
  name = "${var.project_name}-${var.environment}-firehose-policy"
  role = aws_iam_role.firehose_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:AbortMultipartUpload",
          "s3:GetBucketLocation",
          "s3:GetObject",
          "s3:ListBucket",
          "s3:ListBucketMultipartUploads",
          "s3:PutObject"
        ]
        Resource = [
          var.s3_table_bucket_arn,
          "${var.s3_table_bucket_arn}/*",
          aws_s3_bucket.firehose_error_logs.arn,
          "${aws_s3_bucket.firehose_error_logs.arn}/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "s3tables:PutTableData",
          "s3tables:GetTable",
          "s3tables:GetTableBucket"
        ]
        Resource = [
          "arn:aws:s3tables:${var.aws_region}:${data.aws_caller_identity.current.account_id}:bucket/*",
          "arn:aws:s3tables:${var.aws_region}:${data.aws_caller_identity.current.account_id}:bucket/*/namespace/${var.s3_table_namespace}",
          "arn:aws:s3tables:${var.aws_region}:${data.aws_caller_identity.current.account_id}:bucket/*/namespace/${var.s3_table_namespace}/table/${var.s3_table_name}"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "logs:PutLogEvents"
        ]
        Resource = var.enable_cloudwatch_logging ? [
          "${aws_cloudwatch_log_group.firehose_logs[0].arn}:log-stream:${aws_cloudwatch_log_stream.firehose_logs[0].name}"
        ] : []
      },
      {
        Effect = "Allow"
        Action = [
          "glue:GetTable",
          "glue:GetDatabase",
          "glue:GetTableVersion",
          "glue:GetTableVersions"
        ]
        Resource = [
          "arn:aws:glue:${var.aws_region}:${data.aws_caller_identity.current.account_id}:catalog",
          "arn:aws:glue:${var.aws_region}:${data.aws_caller_identity.current.account_id}:database/*",
          "arn:aws:glue:${var.aws_region}:${data.aws_caller_identity.current.account_id}:table/*"
        ]
      }
    ]
  })
}

# Lake Formation Permissions (if enabled)
resource "aws_iam_role_policy" "firehose_lakeformation_policy" {
  count = var.lake_formation_enabled ? 1 : 0

  name = "${var.project_name}-${var.environment}-firehose-lakeformation-policy"
  role = aws_iam_role.firehose_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "lakeformation:GetDataAccess",
          "lakeformation:GrantPermissions"
        ]
        Resource = "*"
      }
    ]
  })
}

# Data source for current AWS account
data "aws_caller_identity" "current" {}

# Kinesis Data Firehose Delivery Stream
resource "aws_kinesis_firehose_delivery_stream" "s3_tables_stream" {
  name        = "${var.project_name}-${var.environment}-s3tables-stream"
  destination = "iceberg"

  iceberg_configuration {
    catalog_arn = "arn:aws:s3tables:${var.aws_region}:${data.aws_caller_identity.current.account_id}:bucket/*"
    role_arn    = aws_iam_role.firehose_role.arn

    s3_configuration {
      role_arn            = aws_iam_role.firehose_role.arn
      bucket_arn          = aws_s3_bucket.firehose_error_logs.arn
      prefix              = "errors/"
      error_output_prefix = "errors/"
      buffering_size      = var.firehose_buffer_size
      buffering_interval  = var.firehose_buffer_interval
      compression_format  = var.firehose_compression_format

      dynamic "cloudwatch_logging_options" {
        for_each = var.enable_cloudwatch_logging ? [1] : []
        content {
          enabled         = true
          log_group_name  = aws_cloudwatch_log_group.firehose_logs[0].name
          log_stream_name = aws_cloudwatch_log_stream.firehose_logs[0].name
        }
      }
    }

    destination_table_configuration {
      table_name             = var.s3_table_name
      database_name          = var.s3_table_namespace
      s3_error_output_prefix = "table-errors/"
    }

    processing_configuration {
      enabled = false
    }

    dynamic "cloudwatch_logging_options" {
      for_each = var.enable_cloudwatch_logging ? [1] : []
      content {
        enabled         = true
        log_group_name  = aws_cloudwatch_log_group.firehose_logs[0].name
        log_stream_name = aws_cloudwatch_log_stream.firehose_logs[0].name
      }
    }
  }

  tags = {
    Name = "${var.project_name}-${var.environment}-s3tables-stream"
  }
}
