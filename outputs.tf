output "firehose_delivery_stream_arn" {
  description = "ARN of the Kinesis Firehose delivery stream"
  value       = aws_kinesis_firehose_delivery_stream.s3_tables_stream.arn
}

output "firehose_delivery_stream_name" {
  description = "Name of the Kinesis Firehose delivery stream"
  value       = aws_kinesis_firehose_delivery_stream.s3_tables_stream.name
}

output "firehose_role_arn" {
  description = "ARN of the IAM role used by Firehose"
  value       = aws_iam_role.firehose_role.arn
}

output "error_logs_bucket_name" {
  description = "Name of the S3 bucket for error logs"
  value       = aws_s3_bucket.firehose_error_logs.id
}

output "error_logs_bucket_arn" {
  description = "ARN of the S3 bucket for error logs"
  value       = aws_s3_bucket.firehose_error_logs.arn
}

output "cloudwatch_log_group_name" {
  description = "Name of the CloudWatch log group (if enabled)"
  value       = var.enable_cloudwatch_logging ? aws_cloudwatch_log_group.firehose_logs[0].name : null
}
