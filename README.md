# Production Minecraft Platform

Minecraftを題材に、AWS・Terraform・CI/CD・セキュリティ・監視・バックアップ・障害復旧を学ぶための個人開発プロジェクトです。

## 目的

Minecraftを常時運用することではなく、AWS上の環境を必要なときだけ構築し、動作確認と障害演習を行い、安全に片付けることを目的としています。

```text
Terraform apply
      ↓
動作確認・障害演習
      ↓
証跡保存
      ↓
Terraform destroy
```

## 学習すること

- TerraformによるAWS基盤の構築
- IAM、VPC、Security Group、EC2、EBS、SSM
- GitHub ActionsとOIDCによるCI/CD
- CloudWatchを使った監視と障害調査
- S3、AWS Backupを使ったバックアップ・復旧
- ECS/Fargate、ECR、ALBによるコンテナ運用
- コスト管理と不要リソースの撤去

Minecraftは最初に小さなVanillaサーバーを使用し、基礎が固まった後にMOD対応を検討します。

## コスト方針

AWSリソースは学習セッション中だけ作成します。常時稼働、固定IP、常設ロードバランサー、長期バックアップなどは前提にしません。

## 現在の状態

設計完了、実装準備中です。今後は小さな構成から順番に実装し、各作業で「構築・確認・撤去」を完了させます。

## 注意事項

このプロジェクトは学習目的です。重要なデータや第三者向けのサービスを載せず、商用環境の可用性や安全性を保証するものではありません。

詳細な設計資料と個人用メモは非公開で管理しています。
