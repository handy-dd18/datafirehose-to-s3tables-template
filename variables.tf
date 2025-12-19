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
}

variable "firehose_buffer_interval" {
  description = "Buffer interval in seconds for Firehose (60-900)"
  type        = number
  default     = 300
}

variable "firehose_compression_format" {
  description = "Compression format for Firehose (UNCOMPRESSED, GZIP, ZIP, SNAPPY, HADOOP_SNAPPY)"
  type        = string
  default     = "GZIP"
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
