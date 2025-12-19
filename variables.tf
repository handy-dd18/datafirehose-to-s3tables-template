variable "aws_region" {
  description = "AWS region where resources will be created"
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Project name used for naming resources"
  type        = string
  default     = "firehose-s3tables"
}

variable "environment" {
  description = "Environment name (e.g., dev, staging, prod)"
  type        = string
  default     = "dev"
}

variable "s3_table_namespace" {
  description = "S3 Tables namespace name"
  type        = string
}

variable "s3_table_name" {
  description = "S3 Tables table name"
  type        = string
}

variable "s3_table_bucket_arn" {
  description = "ARN of the S3 bucket for S3 Tables"
  type        = string
}

variable "firehose_buffer_size" {
  description = "Buffer size in MB for Firehose (1-128)"
  type        = number
  default     = 5

  validation {
    condition     = var.firehose_buffer_size >= 1 && var.firehose_buffer_size <= 128
    error_message = "Buffer size must be between 1 and 128 MB."
  }
}

variable "firehose_buffer_interval" {
  description = "Buffer interval in seconds for Firehose (60-900)"
  type        = number
  default     = 300

  validation {
    condition     = var.firehose_buffer_interval >= 60 && var.firehose_buffer_interval <= 900
    error_message = "Buffer interval must be between 60 and 900 seconds."
  }
}

variable "firehose_compression_format" {
  description = "Compression format for Firehose (UNCOMPRESSED, GZIP, ZIP, SNAPPY, HADOOP_SNAPPY)"
  type        = string
  default     = "GZIP"

  validation {
    condition     = contains(["UNCOMPRESSED", "GZIP", "ZIP", "SNAPPY", "HADOOP_SNAPPY"], var.firehose_compression_format)
    error_message = "Compression format must be one of: UNCOMPRESSED, GZIP, ZIP, SNAPPY, HADOOP_SNAPPY."
  }
}

variable "enable_cloudwatch_logging" {
  description = "Enable CloudWatch logging for Firehose"
  type        = bool
  default     = true
}

variable "lake_formation_enabled" {
  description = "Enable Lake Formation integration"
  type        = bool
  default     = true
}

variable "common_tags" {
  description = "Common tags to apply to all resources"
  type        = map(string)
  default = {
    ManagedBy = "Terraform"
  }
}
