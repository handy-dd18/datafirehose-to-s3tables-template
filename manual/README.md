# Amazon Data Firehose から S3 Tables への直接配信 構築手順書

## 概要

本手順書では、Amazon Data Firehose を使用して IoT サンプルデータを Amazon S3 Tables（Apache Iceberg 形式）に直接配信する環境を構築します。

### アーキテクチャ

```
IoT データ → Amazon Data Firehose → S3 Tables (Apache Iceberg)
                                          ↓
                                    Amazon Athena（クエリ）
```

### 前提条件

#### 動作確認済み環境

- Windows 11 + WSL2 (Ubuntu)

#### 必要なツール

| ツール | バージョン | 用途 |
|--------|-----------|------|
| AWS CLI | v2 以上 | AWS リソースの操作 |
| jq | 任意 | JSON の整形・パース（オプション） |
| base64 | システム標準 | Firehose へのデータ送信時のエンコード |

#### AWS CLI のインストール（WSL2 / Ubuntu）

```bash
# AWS CLI v2 のインストール
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip
sudo ./aws/install

# バージョン確認
aws --version
```

#### AWS CLI の設定

```bash
# プロファイルの設定
aws configure
# または SSO を使用する場合
aws configure sso
```

以下の情報を設定します：
- AWS Access Key ID / Secret Access Key（または SSO 設定）
- Default region: `ap-northeast-1`
- Default output format: `json`

#### 必要な IAM 権限

作業ユーザーには以下のサービスへのアクセス権限が必要です：
- Amazon S3 Tables（`s3tables:*`）
- Amazon S3（`s3:*`）
- Amazon Data Firehose（`firehose:*`）
- Amazon Athena（`athena:*`）
- AWS Glue（`glue:*`）
- AWS Lake Formation（`lakeformation:*`）
- IAM（`iam:*` - ロール・ポリシーの作成に必要）

> **注意**: 本ハンズオンでは管理者権限（AdministratorAccess）での実施を推奨します。

#### その他の前提条件

- AWS マネジメントコンソールへのアクセス権限があること

### 構築リージョン

`ap-northeast-1`（東京リージョン）

---

## 1. サンプル IoT データの作成

Firehose に投入するサンプル IoT データを JSON 形式で作成します。

### サンプルデータ（単一レコード）

```json
{"device_id": "device-001", "temperature": 25.5, "humidity": 60.2, "timestamp": "2025-12-21T10:00:00Z"}
```

### サンプルデータ（複数レコード：テスト用）

```json
{"device_id": "device-001", "temperature": 25.5, "humidity": 60.2, "timestamp": "2025-12-21T10:00:00Z"}
{"device_id": "device-002", "temperature": 26.3, "humidity": 58.1, "timestamp": "2025-12-21T10:01:00Z"}
{"device_id": "device-003", "temperature": 24.8, "humidity": 62.5, "timestamp": "2025-12-21T10:02:00Z"}
```

> **注意**: Firehose は改行区切りの JSON（NDJSON）形式でデータを受け取ります。

---

## 2. 環境変数の設定

以降の手順で使用する環境変数を設定します。テーブルバケット名には一意性を確保するためランダム文字列を付与します。

```bash
# 基本設定
export AWS_REGION="ap-northeast-1"
export ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

# ランダム文字列を生成（8文字）
export RANDOM_SUFFIX=$(cat /dev/urandom | tr -dc 'a-z0-9' | fold -w 8 | head -n 1)

# リソース名の定義
export TABLE_BUCKET_NAME="iot-data-table-bucket-${RANDOM_SUFFIX}"
export NAMESPACE_NAME="iot_sensor_data"
export TABLE_NAME="sensor_readings"
export ERROR_BUCKET_NAME="firehose-error-bucket-${ACCOUNT_ID}-${AWS_REGION}"
export ATHENA_RESULT_BUCKET="s3://aws-athena-query-results-${ACCOUNT_ID}-${AWS_REGION}"

# 確認
echo "TABLE_BUCKET_NAME: ${TABLE_BUCKET_NAME}"
echo "ACCOUNT_ID: ${ACCOUNT_ID}"
```

出力例：
```
TABLE_BUCKET_NAME: iot-data-table-bucket-a1b2c3d4
ACCOUNT_ID: 123456789012
```

> **重要**: この環境変数は現在のシェルセッションでのみ有効です。新しいターミナルを開いた場合は再度設定してください。

---

## 3. S3 Table Bucket の作成

### 3.1 テーブルバケットの作成

```bash
aws s3tables create-table-bucket \
    --region ${AWS_REGION} \
    --name ${TABLE_BUCKET_NAME}
```

### 3.2 作成確認

```bash
aws s3tables list-table-buckets --region ${AWS_REGION}
```

出力例：
```json
{
    "tableBuckets": [
        {
            "arn": "arn:aws:s3tables:ap-northeast-1:123456789012:bucket/iot-data-table-bucket-a1b2c3d4",
            "name": "iot-data-table-bucket-a1b2c3d4",
            "ownerAccountId": "123456789012",
            "createdAt": "2025-12-21T10:00:00.000000+00:00",
            "tableBucketId": "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx",
            "type": "customer"
        }
    ]
}
```

### 3.3 テーブルバケット ARN の取得

```bash
export TABLE_BUCKET_ARN=$(aws s3tables list-table-buckets \
    --region ${AWS_REGION} \
    --query "tableBuckets[?name=='${TABLE_BUCKET_NAME}'].arn" \
    --output text)

echo "TABLE_BUCKET_ARN: ${TABLE_BUCKET_ARN}"
```

> **重要**: テーブルバケット名はリージョン内でアカウントごとに一意である必要があります。削除後もしばらく名前が予約されるため、ランダム文字列を付与しています。

---

## 4. ネームスペースの作成

### 4.1 ネームスペースの作成

```bash
aws s3tables create-namespace \
    --region ${AWS_REGION} \
    --table-bucket-arn ${TABLE_BUCKET_ARN} \
    --namespace ${NAMESPACE_NAME}
```

### 4.2 作成確認

```bash
aws s3tables list-namespaces \
    --region ${AWS_REGION} \
    --table-bucket-arn ${TABLE_BUCKET_ARN}
```

> **注意**: ネームスペース名は小文字、数字、アンダースコア（_）のみ使用可能です。ハイフン（-）は使用できません。

---

## 5. S3 Tables テーブルの作成（スキーマ定義含む）

### 5.1 テーブル定義用 JSON ファイルの作成

S3 Tables では、テーブル作成時にスキーマを定義します。

```bash
cat << EOF > table-definition.json
{
    "tableBucketARN": "${TABLE_BUCKET_ARN}",
    "namespace": "${NAMESPACE_NAME}",
    "name": "${TABLE_NAME}",
    "format": "ICEBERG",
    "metadata": {
        "iceberg": {
            "schema": {
                "fields": [
                    {"name": "device_id", "type": "string", "required": true},
                    {"name": "temperature", "type": "double", "required": false},
                    {"name": "humidity", "type": "double", "required": false},
                    {"name": "timestamp", "type": "string", "required": false}
                ]
            }
        }
    }
}
EOF
```

> **注意**: カラム名はすべて小文字で指定してください。大文字を含むと Lake Formation / Glue Data Catalog でサポートされません。

### 5.2 テーブルの作成

```bash
aws s3tables create-table \
    --region ${AWS_REGION} \
    --cli-input-json file://table-definition.json
```

### 5.3 作成確認

```bash
aws s3tables get-table \
    --region ${AWS_REGION} \
    --table-bucket-arn ${TABLE_BUCKET_ARN} \
    --namespace ${NAMESPACE_NAME} \
    --name ${TABLE_NAME}
```

出力例：
```json
{
    "name": "sensor_readings",
    "type": "customer",
    "tableARN": "arn:aws:s3tables:ap-northeast-1:123456789012:bucket/iot-data-table-bucket-a1b2c3d4/table/xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx",
    "namespace": [
        "iot_sensor_data"
    ],
    "namespaceId": "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx",
    "versionToken": "xxxxxxxxxxxxxxxxxxxx",
    "metadataLocation": "s3://xxxxxxxx-xxxx-xxxx-xxxxxxxxxxxxxxxxxxxxxxxxx--table-s3/metadata/00000-xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx.metadata.json",
    "warehouseLocation": "s3://xxxxxxxx-xxxx-xxxx-xxxxxxxxxxxxxxxxxxxxxxxxx--table-s3",
    "createdAt": "2025-12-21T10:00:00.000000+00:00",
    "createdBy": "123456789012",
    "modifiedAt": "2025-12-21T10:00:00.000000+00:00",
    "ownerAccountId": "123456789012",
    "format": "ICEBERG",
    "tableBucketId": "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
}
```

---

## 6. AWS 分析サービスとの統合を有効化

S3 Tables を Athena や Firehose から利用するために、AWS Glue Data Catalog および Lake Formation との統合を有効化します。

> **注意**: この統合設定は **AWS アカウントのリージョン毎** に1回のみ必要です。S3コンソールからテーブルバケットを作成した場合は、デフォルトで統合が自動的に有効化されます。

### 6.1 統合状況の確認

まず、統合が既に有効化されているか確認します：

```bash
aws glue get-catalog \
    --catalog-id "${ACCOUNT_ID}:s3tablescatalog" \
    --region ${AWS_REGION}
```

カタログ情報が返された場合は **既に統合済み** のため、このステップをスキップしてステップ7に進んでください。

出力例（統合済みの場合）：
```json
{
    "Catalog": {
        "CatalogId": "123456789012:s3tablescatalog",
        "Name": "s3tablescatalog",
        "ResourceArn": "arn:aws:glue:ap-northeast-1:123456789012:catalog/s3tablescatalog",
        "CreateTime": "2025-12-21T00:00:00+09:00",
        "FederatedCatalog": {
            "Identifier": "arn:aws:s3tables:ap-northeast-1:123456789012:bucket/*",
            "ConnectionName": "aws:s3tables",
            "ConnectionType": "aws:s3tables"
        },
        "CatalogProperties": {},
        "CreateTableDefaultPermissions": [],
        "CreateDatabaseDefaultPermissions": [],
        "AllowFullTableExternalDataAccess": "True"
    }
}
```

`EntityNotFoundException` エラーが返された場合は、以下の手順で統合を有効化してください。

### 6.2 AWS マネジメントコンソールでの設定（Lake Formation）

1. **Lake Formation コンソール**（https://console.aws.amazon.com/lakeformation/）を開く
2. ナビゲーションペインで **Data Catalog** > **Catalogs** を選択
3. **Enable S3 Table integration** ボタンをクリック
4. IAM ロールを選択（Lake Formation が認証情報をベンディングするためのロール）
5. **Allow external engines to access data in Amazon S3 locations with full table access** オプションを選択
6. **Enable** ボタンをクリック

### 6.3 AWS CLI での設定（代替方法）

```bash
# ステップ1: S3 Tables カタログをデータロケーションとして登録
aws lakeformation register-resource \
    --resource-arn "arn:aws:s3tables:${AWS_REGION}:${ACCOUNT_ID}:bucket/*" \
    --role-arn "arn:aws:iam::${ACCOUNT_ID}:role/LakeFormationDataAccessRole" \
    --with-federation

# ステップ2: Glue Data Catalog にカタログを作成
aws glue create-catalog \
    --name "s3tablescatalog" \
    --catalog-input '{
        "FederatedCatalog": {
            "Identifier": "arn:aws:s3tables:'${AWS_REGION}':'${ACCOUNT_ID}':bucket/*",
            "ConnectionName": "aws:s3tables"
        },
        "CreateDatabaseDefaultPermissions": [],
        "CreateTableDefaultPermissions": []
    }'
```

> **注意**: AWS CLI での設定には事前に `LakeFormationDataAccessRole` などの適切な IAM ロールが必要です。コンソールでの設定を推奨します。

統合が完了すると、以下が自動的に行われます：
- AWS Glue Data Catalog に `s3tablescatalog` という名前のフェデレーテッドカタログが作成される
- 該当リージョン内のすべてのテーブルバケットが Athena や Firehose から `s3tablescatalog/<テーブルバケット名>` として参照可能になる

参考: [Enabling Amazon S3 Tables integration - AWS Lake Formation](https://docs.aws.amazon.com/lake-formation/latest/dg/enable-s3-tables-catalog-integration.html)

---

## 7. Firehose 用エラー出力 S3 バケットの作成

Firehose の配信エラーログを保存するための通常の S3 バケットを作成します。

### 7.1 S3 バケットの作成

```bash
aws s3 mb s3://${ERROR_BUCKET_NAME} --region ${AWS_REGION}
```

### 7.2 作成確認

```bash
aws s3 ls | grep firehose-error-bucket
```

---

## 8. Athena 用 IAM ロール・ポリシーの作成

### 8.1 信頼ポリシー用 JSON ファイルの作成

```bash
cat << 'EOF' > athena-trust-policy.json
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Principal": {
                "Service": "athena.amazonaws.com"
            },
            "Action": "sts:AssumeRole"
        }
    ]
}
EOF
```

### 8.2 IAM ロールの作成

```bash
aws iam create-role \
    --role-name AthenaS3TablesAccessRole \
    --assume-role-policy-document file://athena-trust-policy.json
```

### 8.3 Athena 用 IAM ポリシーの作成

```bash
cat << EOF > athena-s3tables-policy.json
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Sid": "S3TablesAccess",
            "Effect": "Allow",
            "Action": [
                "s3tables:GetTable",
                "s3tables:GetTableData",
                "s3tables:PutTableData",
                "s3tables:GetNamespace",
                "s3tables:ListNamespaces",
                "s3tables:ListTables",
                "s3tables:GetTableBucket",
                "s3tables:ListTableBuckets",
                "s3tables:UpdateTableMetadataLocation"
            ],
            "Resource": [
                "arn:aws:s3tables:${AWS_REGION}:${ACCOUNT_ID}:bucket/${TABLE_BUCKET_NAME}",
                "arn:aws:s3tables:${AWS_REGION}:${ACCOUNT_ID}:bucket/${TABLE_BUCKET_NAME}/*"
            ]
        },
        {
            "Sid": "GlueCatalogAccess",
            "Effect": "Allow",
            "Action": [
                "glue:GetDatabase",
                "glue:GetDatabases",
                "glue:GetTable",
                "glue:GetTables",
                "glue:GetPartition",
                "glue:GetPartitions",
                "glue:UpdateTable",
                "glue:CreateTable",
                "glue:BatchGetPartition"
            ],
            "Resource": [
                "arn:aws:glue:${AWS_REGION}:${ACCOUNT_ID}:catalog",
                "arn:aws:glue:${AWS_REGION}:${ACCOUNT_ID}:catalog/s3tablescatalog/*",
                "arn:aws:glue:${AWS_REGION}:${ACCOUNT_ID}:database/*",
                "arn:aws:glue:${AWS_REGION}:${ACCOUNT_ID}:table/*/*"
            ]
        },
        {
            "Sid": "AthenaQueryExecution",
            "Effect": "Allow",
            "Action": [
                "athena:StartQueryExecution",
                "athena:GetQueryExecution",
                "athena:GetQueryResults",
                "athena:StopQueryExecution"
            ],
            "Resource": "*"
        },
        {
            "Sid": "AthenaResultsBucket",
            "Effect": "Allow",
            "Action": [
                "s3:GetBucketLocation",
                "s3:GetObject",
                "s3:ListBucket",
                "s3:PutObject"
            ],
            "Resource": [
                "arn:aws:s3:::aws-athena-query-results-${ACCOUNT_ID}-${AWS_REGION}",
                "arn:aws:s3:::aws-athena-query-results-${ACCOUNT_ID}-${AWS_REGION}/*"
            ]
        }
    ]
}
EOF

aws iam create-policy \
    --policy-name AthenaS3TablesAccessPolicy \
    --policy-document file://athena-s3tables-policy.json
```

### 8.4 ポリシーをロールにアタッチ

```bash
aws iam attach-role-policy \
    --role-name AthenaS3TablesAccessRole \
    --policy-arn arn:aws:iam::${ACCOUNT_ID}:policy/AthenaS3TablesAccessPolicy
```

---

## 9. Athena でのサンプルデータ投入と疎通確認

> **注意**: テーブルスキーマはステップ5で定義済みです。ここではAthenaからの疎通確認を行います。

### 9.1 Athena クエリ結果用 S3 バケットの作成（未作成の場合）

```bash
aws s3 mb ${ATHENA_RESULT_BUCKET} --region ${AWS_REGION}
```

### 9.2 Athena クエリ実行用のヘルパー関数定義

AWS CLI で Athena クエリを実行し、結果を取得するためのヘルパー関数を定義します。

```bash
# Athena クエリ実行関数
run_athena_query() {
    local query="$1"
    local catalog="${2:-s3tablescatalog/${TABLE_BUCKET_NAME}}"
    local database="${3:-${NAMESPACE_NAME}}"

    # クエリ実行開始
    QUERY_ID=$(aws athena start-query-execution \
        --query-string "$query" \
        --query-execution-context "Catalog=${catalog},Database=${database}" \
        --result-configuration "OutputLocation=${ATHENA_RESULT_BUCKET}/" \
        --region ${AWS_REGION} \
        --query 'QueryExecutionId' \
        --output text 2>&1)

    # エラーチェック
    if [[ "$QUERY_ID" == *"error"* ]] || [[ -z "$QUERY_ID" ]]; then
        echo "Error starting query: ${QUERY_ID}"
        return 1
    fi

    echo "Query ID: ${QUERY_ID}"

    # クエリ完了まで待機
    while true; do
        STATUS=$(aws athena get-query-execution \
            --query-execution-id "${QUERY_ID}" \
            --region ${AWS_REGION} \
            --query 'QueryExecution.Status.State' \
            --output text)

        echo "Status: ${STATUS}"

        if [ "$STATUS" = "SUCCEEDED" ]; then
            break
        elif [ "$STATUS" = "FAILED" ] || [ "$STATUS" = "CANCELLED" ]; then
            echo "Query failed or cancelled"
            aws athena get-query-execution \
                --query-execution-id "${QUERY_ID}" \
                --region ${AWS_REGION} \
                --query 'QueryExecution.Status.StateChangeReason' \
                --output text
            return 1
        fi

        sleep 2
    done

    # 結果取得
    aws athena get-query-results \
        --query-execution-id "${QUERY_ID}" \
        --region ${AWS_REGION}
}
```

### 9.3 サンプルデータの投入（疎通確認）

```bash
run_athena_query "INSERT INTO \"${NAMESPACE_NAME}\".\"${TABLE_NAME}\" VALUES ('device-test', 20.0, 50.0, '2025-12-21T00:00:00Z')"
```

### 9.4 データ確認

```bash
run_athena_query "SELECT * FROM \"${NAMESPACE_NAME}\".\"${TABLE_NAME}\""
```

出力例：
```json
{
    "ResultSet": {
        "Rows": [
            {
                "Data": [
                    {"VarCharValue": "device_id"},
                    {"VarCharValue": "temperature"},
                    {"VarCharValue": "humidity"},
                    {"VarCharValue": "timestamp"}
                ]
            },
            {
                "Data": [
                    {"VarCharValue": "device-test"},
                    {"VarCharValue": "20.0"},
                    {"VarCharValue": "50.0"},
                    {"VarCharValue": "2025-12-21T00:00:00Z"}
                ]
            }
        ],
        "ResultSetMetadata": {
            "ColumnInfo": [
                {
                    "CatalogName": "hive",
                    "SchemaName": "",
                    "TableName": "",
                    "Name": "device_id",
                    "Label": "device_id",
                    "Type": "varchar",
                    "Precision": 2147483647,
                    "Scale": 0,
                    "Nullable": "UNKNOWN",
                    "CaseSensitive": true
                },
                {
                    "CatalogName": "hive",
                    "SchemaName": "",
                    "TableName": "",
                    "Name": "temperature",
                    "Label": "temperature",
                    "Type": "double",
                    "Precision": 17,
                    "Scale": 0,
                    "Nullable": "UNKNOWN",
                    "CaseSensitive": false
                },
                {
                    "CatalogName": "hive",
                    "SchemaName": "",
                    "TableName": "",
                    "Name": "humidity",
                    "Label": "humidity",
                    "Type": "double",
                    "Precision": 17,
                    "Scale": 0,
                    "Nullable": "UNKNOWN",
                    "CaseSensitive": false
                },
                {
                    "CatalogName": "hive",
                    "SchemaName": "",
                    "TableName": "",
                    "Name": "timestamp",
                    "Label": "timestamp",
                    "Type": "varchar",
                    "Precision": 2147483647,
                    "Scale": 0,
                    "Nullable": "UNKNOWN",
                    "CaseSensitive": true
                }
            ]
        }
    },
    "UpdateCount": 0
}
```

---

## 10. Firehose 用 IAM ロール・ポリシーの作成

### 10.1 信頼ポリシー用 JSON ファイルの作成

```bash
cat << 'EOF' > firehose-trust-policy.json
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Principal": {
                "Service": "firehose.amazonaws.com"
            },
            "Action": "sts:AssumeRole"
        }
    ]
}
EOF
```

### 10.2 IAM ロールの作成

```bash
aws iam create-role \
    --role-name FirehoseS3TablesDeliveryRole \
    --assume-role-policy-document file://firehose-trust-policy.json
```

### 10.3 Firehose 用 IAM ポリシーの作成

```bash
cat << EOF > firehose-s3tables-policy.json
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Sid": "S3TableAccessViaGlueFederation",
            "Effect": "Allow",
            "Action": [
                "glue:GetTable",
                "glue:GetDatabase",
                "glue:GetCatalog",
                "glue:UpdateTable"
            ],
            "Resource": [
                "arn:aws:glue:${AWS_REGION}:${ACCOUNT_ID}:catalog/s3tablescatalog/*",
                "arn:aws:glue:${AWS_REGION}:${ACCOUNT_ID}:catalog/s3tablescatalog",
                "arn:aws:glue:${AWS_REGION}:${ACCOUNT_ID}:catalog",
                "arn:aws:glue:${AWS_REGION}:${ACCOUNT_ID}:database/*",
                "arn:aws:glue:${AWS_REGION}:${ACCOUNT_ID}:table/*/*"
            ]
        },
        {
            "Sid": "LakeFormationDataAccess",
            "Effect": "Allow",
            "Action": [
                "lakeformation:GetDataAccess"
            ],
            "Resource": "*"
        },
        {
            "Sid": "S3TablesDataAccess",
            "Effect": "Allow",
            "Action": [
                "s3tables:GetTable",
                "s3tables:GetTableData",
                "s3tables:PutTableData",
                "s3tables:GetNamespace",
                "s3tables:GetTableBucket",
                "s3tables:UpdateTableMetadataLocation"
            ],
            "Resource": [
                "arn:aws:s3tables:${AWS_REGION}:${ACCOUNT_ID}:bucket/${TABLE_BUCKET_NAME}",
                "arn:aws:s3tables:${AWS_REGION}:${ACCOUNT_ID}:bucket/${TABLE_BUCKET_NAME}/*"
            ]
        },
        {
            "Sid": "S3DeliveryErrorBucketPermission",
            "Effect": "Allow",
            "Action": [
                "s3:AbortMultipartUpload",
                "s3:GetBucketLocation",
                "s3:GetObject",
                "s3:ListBucket",
                "s3:ListBucketMultipartUploads",
                "s3:PutObject"
            ],
            "Resource": [
                "arn:aws:s3:::${ERROR_BUCKET_NAME}",
                "arn:aws:s3:::${ERROR_BUCKET_NAME}/*"
            ]
        },
        {
            "Sid": "CloudWatchLogsPermission",
            "Effect": "Allow",
            "Action": [
                "logs:PutLogEvents",
                "logs:CreateLogStream",
                "logs:CreateLogGroup"
            ],
            "Resource": [
                "arn:aws:logs:${AWS_REGION}:${ACCOUNT_ID}:log-group:/aws/kinesisfirehose/*"
            ]
        }
    ]
}
EOF

aws iam create-policy \
    --policy-name FirehoseS3TablesDeliveryPolicy \
    --policy-document file://firehose-s3tables-policy.json
```

### 10.4 ポリシーをロールにアタッチ

```bash
aws iam attach-role-policy \
    --role-name FirehoseS3TablesDeliveryRole \
    --policy-arn arn:aws:iam::${ACCOUNT_ID}:policy/FirehoseS3TablesDeliveryPolicy
```

---

## 11. Lake Formation での権限付与

Firehose の IAM ロールに対して、Lake Formation で S3 Tables へのアクセス権限を付与します。

### 11.1 データベースレベル権限の付与

```bash
aws lakeformation grant-permissions \
    --principal DataLakePrincipalIdentifier="arn:aws:iam::${ACCOUNT_ID}:role/FirehoseS3TablesDeliveryRole" \
    --resource '{
        "Database": {
            "CatalogId": "'${ACCOUNT_ID}':s3tablescatalog/'${TABLE_BUCKET_NAME}'",
            "Name": "'${NAMESPACE_NAME}'"
        }
    }' \
    --permissions "DESCRIBE" \
    --region ${AWS_REGION}
```

### 11.2 テーブルレベル権限の付与

```bash
aws lakeformation grant-permissions \
    --principal DataLakePrincipalIdentifier="arn:aws:iam::${ACCOUNT_ID}:role/FirehoseS3TablesDeliveryRole" \
    --resource '{
        "Table": {
            "CatalogId": "'${ACCOUNT_ID}':s3tablescatalog/'${TABLE_BUCKET_NAME}'",
            "DatabaseName": "'${NAMESPACE_NAME}'",
            "Name": "'${TABLE_NAME}'"
        }
    }' \
    --permissions "ALL" \
    --region ${AWS_REGION}
```

---

## 12. Amazon Data Firehose の作成

### 12.1 Firehose ストリームの作成（コンソール）

1. **Amazon Data Firehose コンソール** を開く
2. **Firehose ストリームを作成** をクリック
3. 以下の設定を行う:

**ソースと配信先:**
- ソース: `Direct PUT`
- 配信先: `Apache Iceberg Tables`

**Firehose ストリーム名:**
- 名前: `iot-sensor-data-stream`

**配信先の設定:**
- **カタログの選択**: リストから `${TABLE_BUCKET_NAME}` を選択（例: `iot-data-table-bucket`）
- **DestinationDatabaseName（データベース/ネームスペース）**: `iot_sensor_data`
- **DestinationTableName（テーブル）**: `sensor_readings`
- **一意のキー**: 設定なし（または適宜設定）

**S3 バックアップ設定:**
- バックアップバケット: `${ERROR_BUCKET_NAME}`（例: `firehose-error-bucket-123456789012-ap-northeast-1`）
- エラー出力プレフィックス: `errors/`

**バッファのヒント:**
- バッファ間隔: `60` 秒

**IAM ロール:**
- 既存のロールを選択: `FirehoseS3TablesDeliveryRole`

4. **Firehose ストリームを作成** をクリック

### 12.2 AWS CLI での作成（代替方法）

```bash
cat << EOF > firehose-config.json
{
    "DeliveryStreamName": "iot-sensor-data-stream",
    "DeliveryStreamType": "DirectPut",
    "IcebergDestinationConfiguration": {
        "RoleARN": "arn:aws:iam::${ACCOUNT_ID}:role/FirehoseS3TablesDeliveryRole",
        "CatalogConfiguration": {
            "CatalogARN": "arn:aws:glue:${AWS_REGION}:${ACCOUNT_ID}:catalog/s3tablescatalog/${TABLE_BUCKET_NAME}"
        },
        "S3Configuration": {
            "RoleARN": "arn:aws:iam::${ACCOUNT_ID}:role/FirehoseS3TablesDeliveryRole",
            "BucketARN": "arn:aws:s3:::${ERROR_BUCKET_NAME}",
            "Prefix": "",
            "ErrorOutputPrefix": "error/",
            "CloudWatchLoggingOptions": {
                "Enabled": true,
                "LogGroupName": "/aws/kinesisfirehose/iot-sensor-data-stream",
                "LogStreamName": "BackupDelivery"
            }
        },
        "BufferingHints": {
            "IntervalInSeconds": 60
        },
        "CloudWatchLoggingOptions": {
            "Enabled": true,
            "LogGroupName": "/aws/kinesisfirehose/iot-sensor-data-stream",
            "LogStreamName": "DestinationDelivery"
        },
        "DestinationTableConfigurationList": [
            {
                "DestinationDatabaseName": "${NAMESPACE_NAME}",
                "DestinationTableName": "${TABLE_NAME}"
            }
        ]
    }
}
EOF

aws firehose create-delivery-stream \
    --cli-input-json file://firehose-config.json \
    --region ${AWS_REGION}
```

### 12.3 作成確認

```bash
aws firehose describe-delivery-stream \
    --delivery-stream-name iot-sensor-data-stream \
    --region ${AWS_REGION}
```

ステータスが `ACTIVE` になるまで待機します。

---

## 13. Firehose へのサンプルデータ投入

### 13.1 単一レコードの投入

```bash
DATA=$(echo -n '{"device_id": "device-001", "temperature": 25.5, "humidity": 60.2, "timestamp": "2025-12-21T10:00:00Z"}' | base64 -w 0)
aws firehose put-record \
    --delivery-stream-name iot-sensor-data-stream \
    --record "{\"Data\": \"${DATA}\"}" \
    --region ${AWS_REGION}
```

### 13.2 複数レコードの投入

```bash
DATA1=$(echo -n '{"device_id": "device-002", "temperature": 26.3, "humidity": 58.1, "timestamp": "2025-12-21T10:01:00Z"}' | base64 -w 0)
DATA2=$(echo -n '{"device_id": "device-003", "temperature": 24.8, "humidity": 62.5, "timestamp": "2025-12-21T10:02:00Z"}' | base64 -w 0)
DATA3=$(echo -n '{"device_id": "device-004", "temperature": 27.1, "humidity": 55.3, "timestamp": "2025-12-21T10:03:00Z"}' | base64 -w 0)

aws firehose put-record-batch \
    --delivery-stream-name iot-sensor-data-stream \
    --records "[{\"Data\": \"${DATA1}\"}, {\"Data\": \"${DATA2}\"}, {\"Data\": \"${DATA3}\"}]" \
    --region ${AWS_REGION}
```

> **注意**: Firehose はバッファ間隔（60秒）が経過するか、バッファサイズに達するまでデータを保持します。データが S3 Tables に反映されるまで約1〜2分待機してください。

---

## 14. Athena からのデータ確認

### 14.1 データ確認クエリ

Firehose からのデータ投入後、ステップ9.2で定義した `run_athena_query` 関数を使用してデータを確認します。

> **注意**: 関数が未定義の場合は、ステップ9.2のヘルパー関数を再度実行してください。

```bash
run_athena_query "SELECT * FROM \"${NAMESPACE_NAME}\".\"${TABLE_NAME}\" ORDER BY timestamp DESC"
```

出力例：
```json
{
    "ResultSet": {
        "Rows": [
            {
                "Data": [
                    {"VarCharValue": "device_id"},
                    {"VarCharValue": "temperature"},
                    {"VarCharValue": "humidity"},
                    {"VarCharValue": "timestamp"}
                ]
            },
            {
                "Data": [
                    {"VarCharValue": "device-004"},
                    {"VarCharValue": "27.1"},
                    {"VarCharValue": "55.3"},
                    {"VarCharValue": "2025-12-21T10:03:00Z"}
                ]
            },
            {
                "Data": [
                    {"VarCharValue": "device-003"},
                    {"VarCharValue": "24.8"},
                    {"VarCharValue": "62.5"},
                    {"VarCharValue": "2025-12-21T10:02:00Z"}
                ]
            }
        ]
    }
}
```

---

## リソースのクリーンアップ

構築したリソースを削除する場合は、以下の順序で削除します。

> **注意**: 環境変数（`TABLE_BUCKET_ARN`, `ERROR_BUCKET_NAME` 等）が設定されていることを確認してください。未設定の場合はステップ2を再実行してください。

```bash
# 1. Firehose ストリーム削除
aws firehose delete-delivery-stream \
    --delivery-stream-name iot-sensor-data-stream \
    --region ${AWS_REGION}

# 2. S3 Tables テーブル削除
aws s3tables delete-table \
    --region ${AWS_REGION} \
    --table-bucket-arn ${TABLE_BUCKET_ARN} \
    --namespace ${NAMESPACE_NAME} \
    --name ${TABLE_NAME}

# 3. ネームスペース削除
aws s3tables delete-namespace \
    --region ${AWS_REGION} \
    --table-bucket-arn ${TABLE_BUCKET_ARN} \
    --namespace ${NAMESPACE_NAME}

# 4. テーブルバケット削除
aws s3tables delete-table-bucket \
    --region ${AWS_REGION} \
    --table-bucket-arn ${TABLE_BUCKET_ARN}

# 5. エラーバケット削除（中身を空にしてから）
aws s3 rm s3://${ERROR_BUCKET_NAME} --recursive
aws s3 rb s3://${ERROR_BUCKET_NAME}

# 6. IAM ポリシーとロール削除
aws iam detach-role-policy \
    --role-name FirehoseS3TablesDeliveryRole \
    --policy-arn arn:aws:iam::${ACCOUNT_ID}:policy/FirehoseS3TablesDeliveryPolicy
aws iam delete-role --role-name FirehoseS3TablesDeliveryRole
aws iam delete-policy --policy-arn arn:aws:iam::${ACCOUNT_ID}:policy/FirehoseS3TablesDeliveryPolicy

aws iam detach-role-policy \
    --role-name AthenaS3TablesAccessRole \
    --policy-arn arn:aws:iam::${ACCOUNT_ID}:policy/AthenaS3TablesAccessPolicy
aws iam delete-role --role-name AthenaS3TablesAccessRole
aws iam delete-policy --policy-arn arn:aws:iam::${ACCOUNT_ID}:policy/AthenaS3TablesAccessPolicy

# 7. ローカルの JSON ファイル削除
rm -f table-definition.json
rm -f athena-trust-policy.json athena-s3tables-policy.json
rm -f firehose-trust-policy.json firehose-s3tables-policy.json
rm -f firehose-config.json
```

---

## トラブルシューティング

### IAM ポリシー削除時に DeleteConflict エラーが発生する場合

`delete-policy` で `DeleteConflict: This policy has more than one version` エラーが発生した場合、デフォルト以外のバージョンを削除してから再実行してください。

```bash
# ポリシーバージョン一覧を確認
aws iam list-policy-versions \
    --policy-arn arn:aws:iam::${ACCOUNT_ID}:policy/FirehoseS3TablesDeliveryPolicy

# デフォルト以外のバージョンを削除（v2, v3 等を実際のバージョンIDに置き換え）
aws iam delete-policy-version \
    --policy-arn arn:aws:iam::${ACCOUNT_ID}:policy/FirehoseS3TablesDeliveryPolicy \
    --version-id v2

# 全バージョン削除後、ポリシーを削除
aws iam delete-policy --policy-arn arn:aws:iam::${ACCOUNT_ID}:policy/FirehoseS3TablesDeliveryPolicy
```

---

## 参考リンク

- [Deliver data to Apache Iceberg Tables with Amazon Data Firehose](https://docs.aws.amazon.com/firehose/latest/dev/apache-iceberg-destination.html)
- [Streaming data to tables with Amazon Data Firehose](https://docs.aws.amazon.com/AmazonS3/latest/userguide/s3-tables-integrating-firehose.html)
- [Build a data lake for streaming data with Amazon S3 Tables and Amazon Data Firehose](https://aws.amazon.com/blogs/storage/build-a-data-lake-for-streaming-data-with-amazon-s3-tables-and-amazon-data-firehose/)
- [Prerequisites to use Apache Iceberg Tables as a destination](https://docs.aws.amazon.com/firehose/latest/dev/apache-iceberg-prereq.html)
- [Creating a table bucket](https://docs.aws.amazon.com/AmazonS3/latest/userguide/s3-tables-buckets-create.html)
- [Querying Amazon S3 tables with Athena](https://docs.aws.amazon.com/AmazonS3/latest/userguide/s3-tables-integrating-athena.html)

---

**作成日**: 2025年12月21日
**対象リージョン**: ap-northeast-1（東京）
**方式**: リソースリンクなし（新方式・2025年7月31日以降対応）
