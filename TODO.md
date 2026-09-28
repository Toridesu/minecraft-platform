# Production Minecraft Platform — TODO v2.0

## 現在の状況
現在：**T-004-01〜10、T-005-01〜05、T-006完了。費用基準は月10 USD、1回1 USDを目標、1回の見込みが2 USD以上なら新規作成を中止と承認済み。T-101-01〜02完了：Terraform構成にEC2を追加し、14 add / 0 change / 0 destroyの詳細Planを確認。EULAを確認し同意済み。session-runtimeの`apply`は未実施で、今回のPlanによるAWSリソース作成はない。`ExpiresAt`タグは自動停止・削除ではないため、実行時は手動の時間管理と撤去が必要。session-runtimeのstate objectがないことだけではAWS資源の不存在を証明できないため、撤去前にサービス別残置確認を行う。Bootstrapの完全終了は通常cleanupと分離し、S3の`prevent_destroy`とOIDC所有権を個別に扱う。**
次回：T-101-03の事前確認（AWS identity、state、費用・作業時間、手動タイマー）から再開する。まだ`apply`しない。

## 進め方

1回のAWS作業を「作成→確認→証跡→撤去」で閉じる。タスクをまたいでAWSを放置せず、必要なら次回再applyする。依存は学習・コードの準備順であり、前タスクの資源を常設する意味ではない。

チェックは実測と証跡が揃ってから付ける。旧版のタスク番号/完了条件は本一覧で置き換える。非公開の設計資料にあるラボ一覧・受入試験・撤去手順も参照する。

### サブタスクの進め方

- 1つの親タスク（例：`T-003`）を、実行可能な小さなサブタスク（例：`T-003-01`、`T-003-02`）へ分解する。
- サブタスクを開始する前に、学習上の意味、なぜ必要か、今回確認することを説明する。
- その後、実行手順・Bashコマンド・期待結果・失敗時の確認方法を提示する。
- コマンドの実行、AWS操作、結果確認は本人が行う。`apply`、`destroy`、削除などの操作は実行前に対象・費用・戻し方を確認する。
- 本人が結果を共有したら、成功条件と次のサブタスクを一緒に確認する。
- サブタスクの完了条件と証跡が揃ったら、完了したサブタスクの行はこのファイルから削除してよい。`MEMO.md`への記録は任意であり、内容・形式・整理方法は本人が自由に決める。
- 親タスクはサブタスクがすべて完了するまで残し、親タスクの完了条件を満たした時点で完了扱いにする。
- サブタスク完了後は`TODO.md`を直ちに更新し、変更をcommitしてGitHubへpushする。`docs/`・`MEMO.md`はGit対象外。push対象branch・remote・公開対象を確認し、秘密情報を含めない。
- Gitの確認・add・commit・pushはGit Bashで行う。Terraform/AWSのコマンドも原則Bash形式で案内する。

## D0 設計

- [x] D-01 常用プレイの要件を外し、短時間ラボとして要件・構成を再設計。
- [x] D-02 固定費、データ寿命、state分離、KMS/Backup等の個別演習を整理。
- [x] D-03 費用モデル、受入試験、TODO、撤去・記録テンプレートを用意。

## M0 AWSを作る前の準備

- [x] T-001 非公開の入力値台帳を確認。完了：本人承認の月10 USD、1回1 USD目標・見込み2 USD以上で新規作成中止、account、disposable条件、ローカル保存先が明確。
- [x] T-002 当フォルダのGit管理単位とローカルツールを準備。完了：他projectを含めず、state/plan/secret除外、固定版で静的検査可能。依存：T-001。
- [x] T-003 bootstrapの最小S3/OIDC境界/予算メールを設計どおり構築。完了：S3 State作成・保護・backend移行、共有資源の読み取り確認、OIDC Provider/IAM Role/PolicyのApplyと実リソース検証、料金影響の確認。依存：T-002。試験：AT-14、AT-24。
- [x] T-004 AWSなしのPR静的CIを作る。完了：fmt/validate/lint/scanと失敗時停止を確認。PR上の`Terraform Static Checks`は44秒で成功。Workflow定義とActionsログで、AWS認証・AWS CLI・remote backend・`terraform plan/apply/destroy`がないことを確認し、CloudTrailの追加確認は省略。不要な`.terraform`、tfplan、空のlocal stateを削除し、`MEMO.md`、`docs/`、state backupは保持。依存：T-002。試験：AT-09。
- [x] T-005 cleanup仕様・所有物台帳・費用試算を準備。完了：生成物も含む削除順、失敗時再開、bootstrap除外、所有物、費用判断基準、受入条件を整理した。依存：T-001～T-003。試験：AT-13、AT-24の準備。
  - [x] T-005-01 現在のAWSリソースとTerraform管理対象を棚卸しする。完了：Terraform設定からS3 State、GitHub OIDC Provider、Plan/Apply IAM Role・Policy、session-runtime backendを確認。AWS読み取り確認ではBootstrap state objectのみ存在し、session-runtime state objectは見つからなかった。GitHub OIDC Providerは1つ、対象RoleはPlan/Applyの2つ。state外のAWS資源の不存在までは未証明。AWS変更操作は行っていない。
  - [x] T-005-02 cleanup仕様と削除順序を作成する。完了：`docs/14_teardown.md`に、ローカル生成物、session-runtime、Bootstrapの保持・削除境界、通常cleanupの順序、state保持判断、失敗時の再開手順を追記した。AWS変更操作は行っていない。
  - [x] T-005-03 所有物台帳を作成する。完了：個人用`docs/15_resource_ownership.md`に、各リソースの所有者、用途、保持条件、削除判断、確認方法、削除前チェック、更新ルールを記録した。AWS変更操作は行っていない。
  - [x] T-005-04 費用試算と残置・削除判断基準を作成する。完了：個人用`docs/08_cost_roadmap.md`に、1回1 USD目標・月10 USD、1回の見込み2 USD以上なら新規作成中止、Bootstrapの残置方針、runtimeと月額課金リスクのある資源の削除判断、実請求再確認の条件を追記した。AWS変更操作は行っていない。
  - [x] T-005-05 受入条件と再開手順を確認する。完了：`docs/08_cost_roadmap.md`、`docs/14_teardown.md`、`docs/15_resource_ownership.md`を照合し、Bootstrap保持、runtime削除、ローカル生成物整理、費用判断ライン、state有無に応じた再開手順に矛盾がないことを確認した。AWS変更操作は行っていない。
- [x] T-006 非公開のM0理解確認クイズに回答する。完了：T-001〜T-005の費用・state・CI・残置・撤去・Gitを自分の言葉で説明し、安全上重要な判断を確認する。AWS資源は作らない。依存：T-005。T-101へ進む前に完了させる。
  - [x] T-006-01 本人が8問に回答する。完了：資料を参照してもよいので、回答または分からない点をチャットで共有する。
  - [x] T-006-02 回答の理由と誤解を確認する。完了：特に費用、state外資源、残置、Bootstrap完全終了を説明できる。必要なら再回答する。

M0出口：何を作り、いくら使い、どう片付けるかが先に分かる。

## M1 小さなMinecraftと最初の撤去

- [ ] T-101 core profileのVPC/SG/EC2/SSM/systemdを作る。完了：版固定・EULA確認・本人接続・非公開管理。最後に撤去。依存：T-006。試験：AT-02、AT-03、AT-23。
  - [x] T-101-01 Terraform構成にEC2ホストを追加する。完了：固定AMI、`m7i.large`、既存public subnet/SG/SSM Instance Profile、IMDSv2必須、暗号化gp3 root 16 GiBを構成し、fmt/validate/planを実行。Planは14 add / 0 change / 0 destroy。`apply`はしない。
  - [x] T-101-02 Planのリソース・セキュリティ差分をレビューする。完了：network 10件、IAM 3件、EC2 1件を確認。受信はTCP 25565の本人`/32`のみで、SSH/RCON、NAT Gateway、Elastic IP、Interface Endpoint等の想定外リソースなし。PlanのみでAWS変更なし。
  - [ ] T-101-03 apply前の実行条件を確認する。完了：AWS caller identity/regionとremote stateを照合し、見込み費用が1回1 USD目標・2 USD未満であること、作業時間と手動タイマー、撤去手順を確認して本人が開始を判断する。`ExpiresAt`タグを自動停止と誤認しない。まだapplyしない。
    - [x] T-101-03-01 AWSの実行先とsession-runtime stateの有無を読み取り専用で確認する。完了：identityは本人の想定と一致。state objectは404で未作成と確認した。これはstateの不存在を示すだけで、AWSリソース全体の不存在を証明しない。
    - [x] T-101-03-02 前回レビューしたPlanと費用見積りを照合する。完了：Planは14 add / 0 change / 0 destroyで想定どおり。課金対象はm7i.large、gp3 16 GiB、Public IPv4。NAT Gateway/EIP/Interface Endpoint/ALBなし。10分約$0.02、30分約$0.07、90分約$0.21の試算で、1回1 USD目標・2 USD未満の基準を満たす。
    - [ ] T-101-03-03 実験時間・手動タイマー・撤去経路を準備する。完了：作業開始/終了時刻、離席時の対応、Terraform destroyと残置照会の手順を言葉で説明する。
    - [ ] T-101-03-04 Go/No-Goを本人が判断する。完了：前3項目の出力・Plan・撤去方法を確認し、applyへ進むか保留するかを決める。判断だけでapplyしない。
  - [ ] T-101-04 runtimeをapplyし、EC2/ネットワーク/SSMを確認する。完了：本人がapplyを実行し、EC2 running、SSM online、SGの受信範囲、RunId等を証跡化する。SSHを使わない。
  - [ ] T-101-05 Vanilla Javaサーバーを非root・systemdで構成する。完了：公式配布元・版固定、EULA同意を反映、起動/停止/ログを確認する。ゲームの導入はこの段階で初めて行う。
  - [ ] T-101-06 本人接続を試験し、runtimeを撤去する。完了：許可元から接続・保存を確認後、destroyとサービス別残置確認を行い、AWS存在時間・費用確認予定・証跡を記録する。
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

- [ ] T-501 非公開設計資料のAPI契約に沿って実装し、ローカルで認証/入力/SSM結果のテスト。完了：process操作とEC2電源操作を混同しない。依存：M3。
- [ ] T-502 Docker multi-stage、非root、read-only、SIGTERM、scan/SBOM。完了：AWSなしでimageを検査できる。依存：T-501。
- [ ] T-503 ECRとinternal ALB/Fargate/SSM経路を構築。完了：公開HTTPなし、本人がAPIを使え、roleとsecret分離。依存：T-502、T-402。試験：AT-17、AT-18。
- [ ] T-504 digest固定CI/CDと失敗rollbackを実装。完了：task再作成、権限不足、bad health、Terraform収束を確認。依存：T-503。試験：AT-18、AT-19。
- [ ] T-505 ECSセッションを全撤去・再作成。完了：ALB/ENI/task/ECR images/parameter/logsも消し、同じ版で再現。依存：T-504。試験：AT-13、AT-01の一部。

M5出口：Goの機能を増やさず、コンテナの変更・障害・撤去を説明できる。

## M6 全体受入・成果整理

- [ ] T-601 全ATの証跡を整理。完了：独立した再構築3回、S3/AWS Backup/KMS/ECS演習、Postmortem2件。依存：M2～M5。試験：AT-01、AT-22。
- [ ] T-602 実測費用と残置を確認し、必要な未完試験だけ再実行。完了：料金モデルとの差、保持量、請求遅延を説明。依存：T-601。試験：AT-13、AT-14、AT-23。
- [ ] T-603 公開可能な図・理由・試験結果を整理し、休止/完全終了を判断。完了：秘密なし、bootstrapを残すか別手順で撤去するか記録。依存：T-602。試験：AT-24。

連続観察や最低稼働時間を満たすためにAWSを動かさない。学習を終える時は非公開設計資料の完全終了手順も確認する。

## P2 任意（未実施でも全体完成を妨げない）

- [ ] O-01 軽量MODの版固定/互換性/復旧。試験：OT-01。
- [ ] O-02 専用小データでGuardDuty/追加監査/保持ロック。試験：OT-02。
- [ ] O-03 別AZやTLS/DNSの比較。事前見積りと後片付けを必須にする。試験：OT-03。

## 毎回の終了チェック

- [ ] 必要な証跡/教材をローカルへ保存し、復旧/試験の合否を記録。
- [ ] runtime destroy、S3全version/ECR image/recovery point等の整理、data destroy。
- [ ] サービス別に残置確認。失敗/例外は期限と責任者を記録。
- [ ] 後日の請求確認を記録し、次に行う1つのTODOを決める。

**次の1手はT-101-03-03。実験時間・手動タイマー・撤去経路を準備する。まだ`apply`しない。**
