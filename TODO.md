# Production Minecraft Platform — TODO v2.0

現在：**設計更新のみ。実装・AWS作成/削除・GitHub設定は未着手。**

## 進め方

1回のAWS作業を「作成→確認→証跡→撤去」で閉じる。タスクをまたいでAWSを放置せず、必要なら次回再applyする。依存は学習・コードの準備順であり、前タスクの資源を常設する意味ではない。

チェックは実測と証跡が揃ってから付ける。旧版のタスク番号/完了条件は本一覧で置き換える。[ラボ一覧](docs/13_learning_labs.md)、[受入試験](docs/09_acceptance.md)、[撤去手順](docs/14_teardown.md)を併用する。

## D0 設計

- [x] D-01 常用プレイの要件を外し、短時間ラボとして要件・構成を再設計。
- [x] D-02 固定費、データ寿命、state分離、KMS/Backup等の個別演習を整理。
- [x] D-03 費用モデル、受入試験、TODO、撤去・記録テンプレートを用意。

## M0 AWSを作る前の準備

- [ ] T-001 [入力値](docs/11_project_inputs.md)を確認。完了：本人の月額/1回上限、account、disposable条件、ローカル保存先が明確。
- [ ] T-002 当フォルダのGit管理単位とローカルツールを準備。完了：他projectを含めず、state/plan/secret除外、固定版で静的検査可能。依存：T-001。
- [ ] T-003 bootstrapの最小S3/OIDC境界/予算メールを設計どおり構築。完了：state移行・保護、共有資源の棚卸し、料金記録。依存：T-002。試験：AT-14、AT-24。
- [ ] T-004 AWSなしのPR静的CIを作る。完了：fmt/validate/lint/scanと失敗時停止。mergeのみで課金資源を作らない。依存：T-002。試験：AT-09。
- [ ] T-005 cleanup仕様・所有物台帳・費用試算を準備。完了：生成物も含む削除順、失敗時再開、bootstrap除外が説明できる。依存：T-001～T-003。試験：AT-13、AT-24の準備。

M0出口：何を作り、いくら使い、どう片付けるかが先に分かる。

## M1 小さなMinecraftと最初の撤去

- [ ] T-101 core profileのVPC/SG/EC2/SSM/systemdを作る。完了：版固定・EULA確認・本人接続・非公開管理。最後に撤去。依存：M0。試験：AT-02、AT-03、AT-23。
- [ ] T-102 独立data EBS、mount検査、EC2交換を実装。完了：同Worldで再接続し、誤mount時は初期化しない。依存：T-101。試験：AT-04。
- [ ] T-103 session-dataのS3と整合backup/restoreを実装。完了：runtimeを壊しても新EBSに戻せる。依存：T-102。試験：AT-06、AT-07。
- [ ] T-104 最小Agent/Logs/通知を実装。完了：安全な異常から原因を調べ、通知後はalarm/logも撤去。依存：T-101。試験：AT-05。
- [ ] T-105 coreの全撤去と証跡回収を実証。完了：EC2/EBS/S3 versions/Logs等の残置なし、費用確認を記録。依存：T-103、T-104。試験：AT-13、AT-22。

各作業の終わりはdestroy。T-101以降、未完成を理由に起動したまま次週へ持ち越さない。

## M2 復旧・権限・変更失敗の演習

- [ ] T-201 設定/ゲーム更新失敗とrollbackを試す。完了：旧版とWorldの整合を取り戻し、原因・修正を記録。依存：M1。試験：AT-21。
- [ ] T-202 AWS Backupの短期profileを作る。完了：on-demand→新volume復旧→確認→recovery point/volume削除。依存：T-103、T-105。試験：AT-08。
- [ ] T-203 KMSの独立profileを作る。完了：専用keyの許可/拒否・復号・依存整理・削除予約。state等の鍵にしない。依存：T-105。試験：AT-20。
- [ ] T-204 失敗系のRunbook/Postmortemを整理。完了：backup失敗、mount/権限等を事実と仮説に分け、ローカル保存。依存：T-201～T-203。試験：AT-22の準備。

M2出口：保存しただけではなく、消失から戻し、不要な復旧点まで消せる。

## M3 Terraform CI/CDと失敗後cleanup

- [ ] T-301 実際のOIDC claimでplan/apply権限を制限。完了：main等の許可、fork/別repo拒否、最小PassRole。依存：M0。試験：AT-10。
- [ ] T-302 main固定のmanual dispatch、保存plan、排他を実装。完了：SHA/hash/入力不一致拒否、concurrency/S3 lock、公開planなし。依存：T-301。試験：AT-11。
- [ ] T-303 apply→smoke→export→cleanupを実装。完了：テスト失敗でも掃除し、別cleanupから再開可能。依存：T-105、T-302。試験：AT-12。
- [ ] T-304 残置照会と削除境界を試す。完了：誤account/RunId/共有資源を拒否し、生成物も確認。依存：T-303。試験：AT-13、AT-24。

M3出口：成功時だけでなく、途中失敗したAWS作業も安全に終えられる。

## M4 小さな自動化

- [ ] T-401 最小LambdaでEC2状態照会等を試す。完了：IAM Invoke、当該対象のみ、ログと権限を確認して撤去。依存：M3。試験：AT-16。
- [ ] T-402 一回限りSchedulerの期限停止を実装。完了：特定EC2のみstop、期限変更は明示、停止後のcleanupまで試す。依存：T-303。試験：AT-15。

Discord、常設API Gateway、Step Functions/DynamoDBは追加しない。M4前は本人のタイマーで離席前に撤去する。

## M5 ECS/Fargate（ローカル中心、総作業20～40h目安）

- [ ] T-501 [API契約](docs/07_admin_api.md)を実装し、ローカルで認証/入力/SSM結果のテスト。完了：process操作とEC2電源操作を混同しない。依存：M3。
- [ ] T-502 Docker multi-stage、非root、read-only、SIGTERM、scan/SBOM。完了：AWSなしでimageを検査できる。依存：T-501。
- [ ] T-503 ECRとinternal ALB/Fargate/SSM経路を構築。完了：公開HTTPなし、本人がAPIを使え、roleとsecret分離。依存：T-502、T-402。試験：AT-17、AT-18。
- [ ] T-504 digest固定CI/CDと失敗rollbackを実装。完了：task再作成、権限不足、bad health、Terraform収束を確認。依存：T-503。試験：AT-18、AT-19。
- [ ] T-505 ECSセッションを全撤去・再作成。完了：ALB/ENI/task/ECR images/parameter/logsも消し、同じ版で再現。依存：T-504。試験：AT-13、AT-01の一部。

M5出口：Goの機能を増やさず、コンテナの変更・障害・撤去を説明できる。

## M6 全体受入・成果整理

- [ ] T-601 全ATの証跡を整理。完了：独立した再構築3回、S3/AWS Backup/KMS/ECS演習、Postmortem2件。依存：M2～M5。試験：AT-01、AT-22。
- [ ] T-602 実測費用と残置を確認し、必要な未完試験だけ再実行。完了：料金モデルとの差、保持量、請求遅延を説明。依存：T-601。試験：AT-13、AT-14、AT-23。
- [ ] T-603 公開可能な図・理由・試験結果を整理し、休止/完全終了を判断。完了：秘密なし、bootstrapを残すか別手順で撤去するか記録。依存：T-602。試験：AT-24。

連続観察や最低稼働時間を満たすためにAWSを動かさない。学習を終える時は[完全終了](docs/14_teardown.md)も確認する。

## P2 任意（未実施でも全体完成を妨げない）

- [ ] O-01 軽量MODの版固定/互換性/復旧。試験：OT-01。
- [ ] O-02 専用小データでGuardDuty/追加監査/保持ロック。試験：OT-02。
- [ ] O-03 別AZやTLS/DNSの比較。事前見積りと後片付けを必須にする。試験：OT-03。

## 毎回の終了チェック

- [ ] 必要な証跡/教材をローカルへ保存し、復旧/試験の合否を記録。
- [ ] runtime destroy、S3全version/ECR image/recovery point等の整理、data destroy。
- [ ] サービス別に残置確認。失敗/例外は期限と責任者を記録。
- [ ] 後日の請求確認を記録し、次に行う1つのTODOを決める。

**次の1手はT-001。今回の作業ではAWSの作成やdestroyを実行しない。**
