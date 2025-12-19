# Data Firehose to S3 Tables Terraform Template

Amazon Data Firehose を利用してストリーミングデータを S3 Tables に配信する構成を構築する Terraform テンプレート

This Terraform template creates an AWS infrastructure for streaming data ingestion into S3 Tables using Amazon Data Firehose with Lake Formation integration.

## Features

- **Amazon Kinesis Data Firehose**: Automatically scales to handle streaming data ingestion
- **S3 Tables Integration**: Direct delivery to S3 Tables with Iceberg format support
- **Lake Formation Integration**: Built-in support for AWS Lake Formation data governance
- **Error Handling**: Dedicated S3 bucket for error logging and retry handling
- **CloudWatch Monitoring**: Optional CloudWatch Logs integration for monitoring and debugging
- **IAM Security**: Least-privilege IAM roles and policies for secure access
- **Configurable Buffering**: Adjustable buffer size and interval for optimized delivery
- **Data Compression**: Support for multiple compression formats (GZIP, Snappy, etc.)

## Architecture

```
Streaming Data → Kinesis Data Firehose → S3 Tables (Iceberg Format)
                        ↓
                  Error Logs S3 Bucket
                        ↓
                  CloudWatch Logs
```

## Prerequisites

Before using this template, ensure you have:

1. **AWS Account**: Active AWS account with appropriate permissions
2. **Terraform**: Terraform >= 1.0 installed ([Installation Guide](https://www.terraform.io/downloads))
3. **AWS CLI**: AWS CLI configured with credentials ([Setup Guide](https://docs.aws.amazon.com/cli/latest/userguide/cli-chap-configure.html))
4. **S3 Tables Setup**: 
   - S3 Tables bucket created
   - S3 Tables namespace and table configured
   - Table schema defined
5. **Lake Formation**: Lake Formation enabled in your AWS account (if using Lake Formation integration)

## Quick Start

### 1. Clone the Repository

```bash
git clone https://github.com/handy-dd18/datafirehose-to-s3tables-template.git
cd datafirehose-to-s3tables-template
```

### 2. Configure Variables

Create a `terraform.tfvars` file from the example:

```bash
cp examples/terraform.tfvars.example terraform.tfvars
```

Edit `terraform.tfvars` and update the values:

```hcl
aws_region          = "us-east-1"
project_name        = "my-project"
environment         = "dev"
s3_table_namespace  = "your_namespace"
s3_table_name       = "your_table"
s3_table_bucket_arn = "arn:aws:s3:::your-s3-tables-bucket"
```

### 3. Initialize Terraform

```bash
terraform init
```

### 4. Review the Plan

```bash
terraform plan
```

### 5. Apply the Configuration

```bash
terraform apply
```

Type `yes` when prompted to confirm the deployment.

### 6. Verify Deployment

After successful deployment, you can verify the resources:

```bash
# List outputs
terraform output

# Test the Firehose delivery stream
aws firehose put-record \
  --delivery-stream-name $(terraform output -raw firehose_delivery_stream_name) \
  --record '{"Data":"eyJ0ZXN0IjoiZGF0YSJ9Cg=="}'
```

## Configuration

### Required Variables

| Variable | Description | Example |
|----------|-------------|---------|
| `s3_table_namespace` | S3 Tables namespace name | `"my_namespace"` |
| `s3_table_name` | S3 Tables table name | `"my_table"` |
| `s3_table_bucket_arn` | ARN of the S3 bucket for S3 Tables | `"arn:aws:s3:::my-bucket"` |

### Optional Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `aws_region` | AWS region for resources | `"us-east-1"` |
| `project_name` | Project name for resource naming | `"firehose-s3tables"` |
| `environment` | Environment name | `"dev"` |
| `s3_tables_catalog_arn` | S3 Tables catalog ARN (auto-constructed if not provided) | `""` |
| `firehose_buffer_size` | Buffer size in MB (1-128) | `5` |
| `firehose_buffer_interval` | Buffer interval in seconds (60-900) | `300` |
| `firehose_compression_format` | Compression format | `"GZIP"` |
| `enable_cloudwatch_logging` | Enable CloudWatch logging | `true` |
| `lake_formation_enabled` | Enable Lake Formation integration | `true` |
| `common_tags` | Common tags for all resources | `{"ManagedBy": "Terraform"}` |

## Outputs

| Output | Description |
|--------|-------------|
| `firehose_delivery_stream_arn` | ARN of the Kinesis Firehose delivery stream |
| `firehose_delivery_stream_name` | Name of the Kinesis Firehose delivery stream |
| `firehose_role_arn` | ARN of the IAM role used by Firehose |
| `error_logs_bucket_name` | Name of the S3 bucket for error logs |
| `error_logs_bucket_arn` | ARN of the S3 bucket for error logs |
| `cloudwatch_log_group_name` | Name of the CloudWatch log group |

## Lake Formation Integration

This template includes built-in support for AWS Lake Formation. When `lake_formation_enabled = true`:

- The Firehose IAM role is granted Lake Formation permissions
- Proper permissions for `GetDataAccess` and `GrantPermissions` are configured
- The role can interact with Lake Formation-governed S3 Tables

### Additional Lake Formation Setup

You may need to configure additional Lake Formation permissions manually:

```bash
# Grant Firehose role permissions on the S3 Tables location
aws lakeformation grant-permissions \
  --principal DataLakePrincipalIdentifier=$(terraform output -raw firehose_role_arn) \
  --resource '{"Table":{"DatabaseName":"your_namespace","Name":"your_table"}}' \
  --permissions INSERT
```

## Monitoring and Troubleshooting

### CloudWatch Logs

If CloudWatch logging is enabled, you can view Firehose logs:

```bash
aws logs tail $(terraform output -raw cloudwatch_log_group_name) --follow
```

### Error Logs in S3

Check the error logs bucket for failed deliveries:

```bash
aws s3 ls s3://$(terraform output -raw error_logs_bucket_name)/errors/ --recursive
```

### Firehose Metrics

Monitor Firehose metrics in CloudWatch:

- DeliveryToS3.Success
- DeliveryToS3.DataFreshness
- IncomingBytes
- IncomingRecords

## Data Ingestion

### Using AWS SDK (Python)

```python
import boto3
import json

firehose = boto3.client('firehose')

# Prepare your data
data = {
    "id": 1,
    "name": "example",
    "timestamp": "2024-01-01T00:00:00Z"
}

# Send to Firehose
response = firehose.put_record(
    DeliveryStreamName='your-stream-name',
    Record={
        'Data': json.dumps(data) + '\n'
    }
)
```

### Batch Records

```python
records = [
    {'Data': json.dumps(record) + '\n'}
    for record in your_data_list
]

response = firehose.put_record_batch(
    DeliveryStreamName='your-stream-name',
    Records=records
)
```

## Best Practices

1. **Buffer Configuration**: Adjust `firehose_buffer_size` and `firehose_buffer_interval` based on your data volume and latency requirements
2. **Compression**: Use GZIP compression to reduce storage costs
3. **Monitoring**: Enable CloudWatch logging for production environments
4. **Error Handling**: Regularly monitor the error logs bucket for failed deliveries
5. **Security**: Use least-privilege IAM policies and enable encryption at rest
6. **Testing**: Test with sample data before deploying to production

## Cost Optimization

- Adjust buffer settings to batch records efficiently
- Enable compression to reduce storage costs
- Monitor CloudWatch costs and adjust log retention as needed
- Use S3 lifecycle policies for error logs bucket

## Security Considerations

- All S3 buckets have public access blocked by default
- IAM roles follow the principle of least privilege
- Error logs bucket has versioning enabled
- Consider enabling S3 bucket encryption and CloudWatch Logs encryption for sensitive data

## Cleanup

To destroy all resources created by this template:

```bash
terraform destroy
```

**Warning**: This will delete all resources, including the error logs bucket. Ensure you have backed up any important data before destroying.

## Support and Contribution

For issues, questions, or contributions:

- Open an issue on GitHub
- Submit a pull request with improvements
- Contact the maintainers

## License

This template is provided as-is for use with AWS services.

## Additional Resources

- [Amazon Kinesis Data Firehose Documentation](https://docs.aws.amazon.com/firehose/)
- [AWS S3 Tables Documentation](https://docs.aws.amazon.com/s3tables/)
- [AWS Lake Formation Documentation](https://docs.aws.amazon.com/lake-formation/)
- [Terraform AWS Provider Documentation](https://registry.terraform.io/providers/hashicorp/aws/latest/docs)
