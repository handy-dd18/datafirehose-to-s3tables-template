# Data Firehose から S3 Tables への Terraform テンプレート

Amazon Data Firehose を利用してストリーミングデータを S3 Tables に配信する構成を構築する Terraform テンプレート

このテンプレートは、Amazon Data Firehose と Lake Formation の統合を使用して、S3 Tables へのストリーミングデータ取り込みのための AWS インフラストラクチャを作成します。

## 機能

- **Amazon Kinesis Data Firehose**: ストリーミングデータの取り込みを自動スケーリングで処理
- **S3 Tables 統合**: Iceberg フォーマットのサポートにより S3 Tables への直接配信
- **Lake Formation 統合**: AWS Lake Formation データガバナンスのビルトインサポート
- **エラーハンドリング**: エラーログとリトライ処理用の専用 S3 バケット
- **CloudWatch モニタリング**: モニタリングとデバッグのためのオプションの CloudWatch Logs 統合
- **IAM セキュリティ**: セキュアなアクセスのための最小権限 IAM ロールとポリシー
- **設定可能なバッファリング**: 最適化された配信のための調整可能なバッファサイズとインターバル
- **データ圧縮**: 複数の圧縮フォーマット（GZIP、Snappy など）のサポート

## アーキテクチャ

```
ストリーミングデータ → Kinesis Data Firehose → S3 Tables (Iceberg フォーマット)
                              ↓
                        エラーログ S3 バケット
                              ↓
                        CloudWatch Logs
```

## 前提条件

このテンプレートを使用する前に、以下を確認してください：

1. **AWS アカウント**: 適切な権限を持つアクティブな AWS アカウント
2. **Terraform**: Terraform >= 1.0 がインストールされていること（[インストールガイド](https://www.terraform.io/downloads)）
3. **AWS CLI**: 認証情報が設定された AWS CLI（[セットアップガイド](https://docs.aws.amazon.com/cli/latest/userguide/cli-chap-configure.html)）
4. **S3 Tables のセットアップ**: 
   - S3 Tables バケットが作成されていること
   - S3 Tables の名前空間とテーブルが設定されていること
   - テーブルスキーマが定義されていること
5. **Lake Formation**: Lake Formation 統合を使用する場合、AWS アカウントで Lake Formation が有効になっていること

## クイックスタート

### 1. リポジトリのクローン

```bash
git clone https://github.com/handy-dd18/datafirehose-to-s3tables-template.git
cd datafirehose-to-s3tables-template
```

### 2. 変数の設定

サンプルから `terraform.tfvars` ファイルを作成します：

```bash
cp examples/terraform.tfvars.example terraform.tfvars
```

`terraform.tfvars` を編集して値を更新します：

```hcl
aws_region          = "us-east-1"
project_name        = "my-project"
environment         = "dev"
s3_table_namespace  = "your_namespace"
s3_table_name       = "your_table"
s3_table_bucket_arn = "arn:aws:s3:::your-s3-tables-bucket"
```

### 3. Terraform の初期化

```bash
terraform init
```

### 4. プランの確認

```bash
terraform plan
```

### 5. 設定の適用

```bash
terraform apply
```

デプロイを確認するため、プロンプトが表示されたら `yes` と入力してください。

### 6. デプロイの検証

デプロイが成功したら、リソースを検証できます：

```bash
# 出力の一覧表示
terraform output

# Firehose 配信ストリームのテスト
aws firehose put-record \
  --delivery-stream-name $(terraform output -raw firehose_delivery_stream_name) \
  --record '{"Data":"eyJ0ZXN0IjoiZGF0YSJ9Cg=="}'
```

## 設定

### 必須変数

| 変数 | 説明 | 例 |
|----------|-------------|---------|
| `s3_table_namespace` | S3 Tables の名前空間名 | `"my_namespace"` |
| `s3_table_name` | S3 Tables のテーブル名 | `"my_table"` |
| `s3_table_bucket_arn` | S3 Tables 用の S3 バケットの ARN | `"arn:aws:s3:::my-bucket"` |

### オプション変数

| 変数 | 説明 | デフォルト値 |
|----------|-------------|---------|
| `aws_region` | リソースの AWS リージョン | `"us-east-1"` |
| `project_name` | リソース命名用のプロジェクト名 | `"firehose-s3tables"` |
| `environment` | 環境名 | `"dev"` |
| `s3_tables_catalog_arn` | S3 Tables カタログ ARN（指定しない場合は自動構築） | `""` |
| `firehose_buffer_size` | バッファサイズ（MB、1-128） | `5` |
| `firehose_buffer_interval` | バッファインターバル（秒、60-900） | `300` |
| `firehose_compression_format` | 圧縮フォーマット | `"GZIP"` |
| `enable_cloudwatch_logging` | CloudWatch ログ記録を有効化 | `true` |
| `lake_formation_enabled` | Lake Formation 統合を有効化 | `true` |
| `common_tags` | すべてのリソースに適用される共通タグ | `{"ManagedBy": "Terraform"}` |

## 出力

| 出力 | 説明 |
|--------|-------------|
| `firehose_delivery_stream_arn` | Kinesis Firehose 配信ストリームの ARN |
| `firehose_delivery_stream_name` | Kinesis Firehose 配信ストリームの名前 |
| `firehose_role_arn` | Firehose が使用する IAM ロールの ARN |
| `error_logs_bucket_name` | エラーログ用 S3 バケットの名前 |
| `error_logs_bucket_arn` | エラーログ用 S3 バケットの ARN |
| `cloudwatch_log_group_name` | CloudWatch ロググループの名前 |

## Lake Formation 統合

このテンプレートは AWS Lake Formation のビルトインサポートを含みます。`lake_formation_enabled = true` の場合：

- Firehose IAM ロールに Lake Formation のアクセス許可が付与されます
- `GetDataAccess` と `GrantPermissions` の適切な権限が設定されます
- Lake Formation で管理される S3 Tables とロールが連携できます

### 追加の Lake Formation セットアップ

追加の Lake Formation 権限を手動で設定する必要がある場合があります：

```bash
# S3 Tables の場所に対して Firehose ロールに権限を付与
aws lakeformation grant-permissions \
  --principal DataLakePrincipalIdentifier=$(terraform output -raw firehose_role_arn) \
  --resource '{"Table":{"DatabaseName":"your_namespace","Name":"your_table"}}' \
  --permissions INSERT
```

## モニタリングとトラブルシューティング

### CloudWatch Logs

CloudWatch ログ記録が有効な場合、Firehose ログを表示できます：

```bash
aws logs tail $(terraform output -raw cloudwatch_log_group_name) --follow
```

### S3 のエラーログ

配信失敗のエラーログバケットを確認します：

```bash
aws s3 ls s3://$(terraform output -raw error_logs_bucket_name)/errors/ --recursive
```

### Firehose メトリクス

CloudWatch で Firehose メトリクスをモニタリングします：

- DeliveryToS3.Success
- DeliveryToS3.DataFreshness
- IncomingBytes
- IncomingRecords

## データの取り込み

### AWS SDK の使用（Python）

```python
import boto3
import json

firehose = boto3.client('firehose')

# データの準備
data = {
    "id": 1,
    "name": "example",
    "timestamp": "2024-01-01T00:00:00Z"
}

# Firehose への送信
response = firehose.put_record(
    DeliveryStreamName='your-stream-name',
    Record={
        'Data': json.dumps(data) + '\n'
    }
)
```

### バッチレコード

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

## ベストプラクティス

1. **バッファ設定**: データ量とレイテンシー要件に基づいて `firehose_buffer_size` と `firehose_buffer_interval` を調整してください
2. **圧縮**: ストレージコストを削減するため GZIP 圧縮を使用してください
3. **モニタリング**: 本番環境では CloudWatch ログ記録を有効にしてください
4. **エラー処理**: 配信失敗に関してエラーログバケットを定期的にモニタリングしてください
5. **セキュリティ**: 最小権限 IAM ポリシーを使用し、保存時の暗号化を有効にしてください
6. **テスト**: 本番環境にデプロイする前にサンプルデータでテストしてください

## コスト最適化

- レコードを効率的にバッチ処理するためバッファ設定を調整
- ストレージコスト削減のため圧縮を有効化
- CloudWatch コストをモニタリングし、必要に応じてログ保持期間を調整
- エラーログバケットに S3 ライフサイクルポリシーを使用

## セキュリティに関する考慮事項

- すべての S3 バケットはデフォルトでパブリックアクセスがブロックされています
- IAM ロールは最小権限の原則に従います
- エラーログバケットはバージョニングが有効です
- 機密データには S3 バケット暗号化と CloudWatch Logs 暗号化の有効化を検討してください

## クリーンアップ

このテンプレートで作成したすべてのリソースを削除するには：

```bash
terraform destroy
```

**警告**: これによりエラーログバケットを含むすべてのリソースが削除されます。削除する前に重要なデータをバックアップしていることを確認してください。

## サポートと貢献

問題、質問、または貢献については：

- GitHub で Issue を作成
- 改善のためのプルリクエストを提出
- メンテナーに連絡

## ライセンス

このテンプレートは AWS サービスでの使用のために現状のまま提供されます。

## 追加リソース

- [Amazon Kinesis Data Firehose ドキュメント](https://docs.aws.amazon.com/firehose/)
- [AWS S3 Tables ドキュメント](https://docs.aws.amazon.com/s3tables/)
- [AWS Lake Formation ドキュメント](https://docs.aws.amazon.com/lake-formation/)
- [Terraform AWS Provider ドキュメント](https://registry.terraform.io/providers/hashicorp/aws/latest/docs)
