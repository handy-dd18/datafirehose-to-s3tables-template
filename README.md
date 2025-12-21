# Amazon Data Firehose to S3 Tables ハンズオン

Amazon Data Firehose から S3 Tables（Apache Iceberg 形式）へのストリーミングデータ配信環境を構築するハンズオンワークショップです。

## 概要

このハンズオンでは、IoT センサーデータを模したサンプルデータを Amazon Data Firehose 経由で S3 Tables（Apache Iceberg 形式）に配信し、Amazon Athena でクエリする一連の流れを体験します。

### 学べること

- S3 Tables（テーブルバケット、ネームスペース、テーブル）の作成と設定
- AWS Glue Data Catalog / Lake Formation との統合設定
- Amazon Data Firehose の Iceberg 配信先設定
- Amazon Athena を使用した Iceberg テーブルへのクエリ

### アーキテクチャ

```
IoT データ → Amazon Data Firehose → S3 Tables (Apache Iceberg)
                                          ↓
                                    Amazon Athena（クエリ）
```

## 手順の進捗状況

| 方式 | フォルダ | 状態 | 説明 |
|------|----------|------|------|
| 手動構築 | `manual/` | **完了** | AWS CLI とマネジメントコンソールを使用した手順 |
| IaC | `terraform/` | **作成中** | Terraform による自動構築 |

## フォルダ構成

```
.
├── README.md
├── manual/                          # 手動構築手順
│   └── README.md
└── terraform/                       # IaC（Terraform）による構築
    └── README.md
```

## 対象リージョン

ap-northeast-1（東京）

## 参考

- [Streaming data to tables with Amazon Data Firehose](https://docs.aws.amazon.com/AmazonS3/latest/userguide/s3-tables-integrating-firehose.html)
