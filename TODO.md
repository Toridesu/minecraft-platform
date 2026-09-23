# Production Minecraft Platform — TODO v2.0

現在：**bootstrapのS3 State作成・S3 backend移行、OIDC Provider/IAM Role/PolicyのApply・実リソース確認まで完了。GitHub CI/CD・Minecraft実装は未着手。**

## 進め方

1回のAWS作業を「作成→確認→証跡→撤去」で閉じる。タスクをまたいでAWSを放置せず、必要なら次回再applyする。依存は学習・コードの準備順であり、前タスクの資源を常設する意味ではない。

チェックは実測と証跡が揃ってから付ける。旧版のタスク番号/完了条件は本一覧で置き換える。[ラボ一覧](docs/13_learning_labs.md)、[受入試験](docs/09_acceptance.md)、[撤去手順](docs/14_teardown.md)を併用する。

### サブタスクの進め方

- 1つの親タスク（例：`T-003`）を、実行可能な小さなサブタスク（例：`T-003-01`、`T-003-02`）へ分解する。
- サブタスクを開始する前に、学習上の意味、なぜ必要か、今回確認することを説明する。
- その後、実行手順・Bashコマンド・期待結果・失敗時の確認方法を提示する。
- コマンドの実行、AWS操作、結果確認は本人が行う。`apply`、`destroy`、削除などの操作は実行前に対象・費用・戻し方を確認する。
- 本人が結果を共有したら、成功条件と次のサブタスクを一緒に確認する。
- サブタスクの完了条件と証跡が揃ったら、完了したサブタスクの行はこのファイルから削除してよい。`MEMO.md`への記録は任意であり、内容・形式・整理方法は本人が自由に決める。
- 親タスクはサブタスクがすべて完了するまで残し、親タスクの完了条件を満たした時点で完了扱いにする。
- サブタスク完了後は、`TODO.md`を直ちに更新し、変更をコミットしてGitHubへpushする。push前に対象branch・remote・公開対象を確認し、`docs/`・`MEMO.md`・秘密情報は含めない。

## D0 設計

- [x] D-01 常用プレイの要件を外し、短時間ラボとして要件・構成を再設計。
- [x] D-02 固定費、データ寿命、state分離、KMS/Backup等の個別演習を整理。
- [x] D-03 費用モデル、受入試験、TODO、撤去・記録テンプレートを用意。

## M0 AWSを作る前の準備

- [x] T-001 [入力値](docs/11_project_inputs.md)を確認。完了：本人の月額/1回上限、account、disposable条件、ローカル保存先が明確。
- [x] T-002 当フォルダのGit管理単位とローカルツールを準備。完了：他projectを含めず、state/plan/secret除外、固定版で静的検査可能。依存：T-001。
- [x] T-003 bootstrapの最小S3/OIDC境界/予算メールを設計どおり構築。完了：S3 State作成・保護・backend移行、共有資源の読み取り確認、OIDC Provider/IAM Role/PolicyのApplyと実リソース検証、料金影響の確認。依存：T-002。試験：AT-14、AT-24。
- [ ] T-004 AWSなしのPR静的CIを作る。完了：fmt/validate/lint/scanと失敗時停止。AWS認証・remote backend・plan/apply/destroyを含めず、mergeのみで課金資源を作らない。依存：T-002。試験：AT-09。
  - [x] T-004-01 Git境界とCI対象を確認する。完了：Git root/remote/対象branchを確認し、`docs/`、`MEMO.md`、state、plan、secret、ローカル証跡がGit対象外であることを確認。AWS認証情報をCIへ渡さない方針を決める。
  - [x] T-004-02 ローカル検査ツールを確認する。完了：Terraform、TFLint、Trivy、Gitの利用可否と固定候補版を記録。未導入なら導入方法と公式配布元を確認し、無関係なツールは追加しない。
- [ ] T-004-03 Terraformの静的検査をローカルで成立させる。完了：対象rootごとに`terraform fmt -check`、`terraform init -backend=false`、`terraform validate`が通る。backendなしのためremote state/AWS APIを使わないことを確認。
  - [x] T-004-03-01 Terraformの要求版、対象root、Git状態を確認。完了：Terraform v1.15.8、bootstrap/runtimeの`versions.tf`、Git状態を確認し、AWS APIを使っていない。最新版への更新は要求版固定のため保留。
  - [ ] T-004-04 Lint・セキュリティ検査の基準を決める。完了：`.tflint.hcl`、`tflint --init`、`tflint`、Trivyのconfig/secret scanを最小構成で実行。除外は理由・期限を残し、警告の無条件無視をしない。
  - [ ] T-004-05 GitHub Actions workflowを設計する。完了：`pull_request`と手動実行だけを起点にし、`permissions: contents: read`、固定SHAのAction、AWS認証なし、backendなし検査、失敗時停止を設計レビュー。
  - [ ] T-004-06 静的CI設定を実装する。完了：workflowと必要最小限の設定ファイルを追加。`id-token: write`、`configure-aws-credentials`、`terraform plan/apply/destroy`、AWS CLI実行を含めない。
  - [ ] T-004-07 正常系をローカルで検証する。完了：fmt/validate/lint/scanがすべて成功し、出力にsecret/state/個人用資料が含まれない。
  - [ ] T-004-08 失敗系を安全に検証する。完了：専用の一時branchまたは一時ファイルでformat/validate/lint/secretの少なくとも1件を失敗させ、検査が停止することを確認。試験後は一時変更を明示して取り除く。
  - [ ] T-004-09 GitHub上のPRで検証する。完了：Actionsが成功・失敗を正しく表示し、AWSリソース作成・AWS認証・remote stateアクセスが発生しないことをworkflow/log/CloudTrail Event historyで確認。
  - [ ] T-004-10 受入と後片付けを行う。完了：AT-09の証跡、利用したActions分数の確認、不要artifactの削除、残る設定の確認。全サブタスク完了後は本一覧からサブタスク行を削除し、親T-004を完了にする。
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

**次の1手はT-004-03。AWS providerの認証確認を切り分け、AWS APIなしで静的検査を成立させる。**
