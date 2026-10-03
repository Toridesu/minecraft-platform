# Production Minecraft Platform — TODO v2.0

## 現在の状況
現在：**T-004-01〜10、T-005-01〜05、T-006、T-101-01〜06完了。費用基準は月10 USD、1回1 USDを目標、1回の見込みが2 USD以上なら新規作成を中止と承認済み。2026-09-29のsession-runtime applyは14 add / 0 change / 0 destroy、destroyは14 destroyed。Minecraft Java 26.1をMicrosoft OpenJDK 25.0.4.1で起動し、配布物のSHA検証、EULA同意、非rootユーザー・systemd起動停止を確認。本人クライアントから接続し、ログイン・切断を確認。SIGTERM由来の終了コード143はsystemdで成功扱いとなり、サービスは`inactive (dead)`。session-runtime stateは空。EC2/EBS/Public IPv4、VPC/Endpoint等ネットワーク、Minecraft専用IAMはサービス別照会で該当なし。BootstrapのS3 bucketとstate objectは存在し、Bootstrap stateの管理資源一覧も確認。`ExpiresAt`タグの日時を過ぎてもEC2は自動停止しなかったため、タグは自動cleanupではないと実証。90分の約$0.21は事前見積りで実費ではない。実際の請求額はAWS Billing/Cost Explorer反映後に確認する。Bootstrapは通常保持し、完全終了は別手順とする。**
2026-10-03：T-102-01完了。独立した暗号化gp3 16 GiBのdata EBSとattachmentを追加し、既存のAWS管理キーを参照。本人がfmt/validate、実行先・default workspace・空のruntime stateを確認し、Plan 16 add / 0 change / 0 destroyを確認後、16 resourceのapplyを完了。
T-102-02完了：起動前検査、systemd service、mount・識別情報のテンプレートを作成。本人がLinuxコンテナで模擬応答によるテストを実行し、11 passed / 0 failedを確認。実EBSのmountとsystemdによる起動拒否は未検証で、T-102-03に残す。
T-102-03進行中：本人が初回data EBSの識別・初期化、mount、権限、固定版JDK/JAR、起動前検査・systemd設定を配置。本人の明示依頼により、以降のAWS操作はCodexが実施。実systemdでUUID不一致・volume ID不一致・mount不可による起動拒否、Java未起動・空World未生成を確認。正常起動・停止後のWorld全25ファイルのSHA-256を記録し、unmount後にEC2とattachmentのみ交換（2 add / 0 change / 2 destroy）。同じdata EBS・UUIDを再利用し、formatせず全25ファイルの一致と既存Worldの正常起動を確認。本人のゲーム接続と撤去は未完了。現在runtimeは稼働・課金中。証跡はGit対象外の`evidence/`に保存。
次の操作：交換後EC2へ本人が接続・切断したら、正常停止、runtime destroy、サービス別残置確認を行う。完了までT-102は未チェック。T-101/T-102の実費は請求反映後に確認して追記する。

## 進め方

1回のAWS作業を「作成→確認→証跡→撤去」で閉じる。タスクをまたいでAWSを放置せず、必要なら次回再applyする。依存は学習・コードの準備順であり、前タスクの資源を常設する意味ではない。
チェックは実測と証跡が揃ってから付ける。旧版のタスク番号/完了条件は本一覧で置き換える。非公開の設計資料にあるラボ一覧・受入試験・撤去手順も参照する。

### サブタスクの進め方

- 目的は学習。Codexが一気に実行するのではなく、本人が理解しながら自分で進められるよう案内する。
- 1つの親タスク（例：`T-003`）を、実行可能な小さなサブタスク（例：`T-003-01`、`T-003-02`）へ分解する。サブタスクの中にさらにサブタスクを作らない。
- サブタスクを開始する前に、学習上の意味、なぜ必要か、今回確認することを説明し、その後に実行手順・Bashコマンド・期待結果・失敗時の確認方法を提示する。
- 本人が結果を共有したら成功条件を確認し、確認が済んでから次のサブタスクへ進む。
- サブタスクの完了条件と証跡が揃ったらTODO.mdを更新し、そのサブタスクを完了扱いにする。親タスク内の全サブタスクが完了したら、完了したサブタスクの行はこのファイルから削除してよい。
- `README.md`は外部公開向けに簡潔に保つ。`docs/`と`MEMO.md`は非公開資料としてGitHubへpushしない。`MEMO.md`は本人専用の雑多メモであり、Codexは記録・管理・整理をしない。
- サブエージェントは使わない。
- 親タスクはサブタスクがすべて完了するまで残し、親タスクの完了条件を満たした時点で完了扱いにする。
- Gitの確認・add・commit・pushはGit Bashで行う。Terraform/AWSのコマンドも原則Bash形式で案内する。
- サブタスクを作成する際は、必要最低限にすること。冗長なのは辞めて、学習に必要ならその限りではない。

## D0 設計

- [x] D-01 常用プレイの要件を外し、短時間ラボとして要件・構成を再設計。
- [x] D-02 固定費、データ寿命、state分離、KMS/Backup等の個別演習を整理。
- [x] D-03 費用モデル、受入試験、TODO、撤去・記録テンプレートを用意。

## M0 AWSを作る前の準備

- [x] T-001 非公開の入力値台帳を確認。完了：本人承認の月10 USD、1回1 USD目標・見込み2 USD以上で新規作成中止、account、disposable条件、ローカル保存先が明確。
- [x] T-002 当フォルダのGit管理単位とローカルツールを準備。完了：他projectを含めず、state/plan/secret除外、固定版で静的検査可能。依存：T-001。
- [x] T-003 bootstrapの最小S3/OIDC境界/予算メールを設計どおり構築。完了：S3 State作成・保護・backend移行、共有資源の読み取り確認、OIDC Provider/IAM Role/PolicyのApplyと実リソース検証、料金影響の確認。依存：T-002。試験：AT-14、AT-24。
- [x] T-004 AWSなしのPR静的CIを作る。完了：fmt/validate/lint/scanと失敗時停止を確認。PR上の`Terraform Static Checks`は44秒で成功。Workflow定義とActionsログで、AWS認証・AWS CLI・remote backend・`terraform plan/apply/destroy`がないことを確認し、CloudTrailの追加確認は省略。不要な`.terraform`、tfplan、空のlocal stateを削除し、`MEMO.md`、`docs/`、state backupは保持。依存：T-002。試験：AT-09。
- [x] T-006 非公開のM0理解確認クイズに回答する。完了：T-001〜T-005の費用・state・CI・残置・撤去・Gitを自分の言葉で説明し、安全上重要な判断を確認する。AWS資源は作らない。依存：T-005。T-101へ進む前に完了させる。

M0出口：何を作り、いくら使い、どう片付けるかが先に分かる。

## M1 小さなMinecraftと最初の撤去

T-101の順序：03-01〜03-04でapply前条件を確認済み。今回、ローカルのMinecraft/JDK版固定を済ませる前にruntimeを起動したため、T-101-05で公式配布元・版・ハッシュを確認した。AWS上の実行順はT-101-04（完了）→T-101-05（完了）→T-101-06（完了）。

AWS上の実行順：T-101-04（runtime作成と確認）→ T-101-05（サーバー設定）→ T-101-06（接続試験と撤去）。接続試験・runtime destroy・サービス別残置確認は完了。Bootstrapとstate bucketは保持し、実費請求の反映だけ後日確認する。

- [x] T-101 core profileのVPC/SG/EC2/SSM/systemdを作り、実験後に撤去する。完了：版固定・EULA確認・本人接続・非公開管理を行い、14 resourceをdestroy。stateは空で、EC2/EBS/Public IPv4/専用network/IAMの残置なし。Bootstrapは保持。実費の請求反映を後日確認する。依存：T-006。試験：AT-02、AT-03、AT-23。
- [ ] T-102 独立data EBS、mount検査、EC2交換を実装。完了：同Worldで再接続し、誤mount時は初期化しない。依存：T-101。試験：AT-04。
  - [x] T-102-01 Terraformに暗号化data EBSとEC2 attachmentを追加し、Planを確認。完了：独立resourceとしてgp3 16 GiB・暗号化・AWS管理キー・subnetと同じAZ・EC2 attachmentを定義。本人がfmt/validate成功、実行先・default workspace・空のruntime state、Plan 16 add / 0 change / 0 destroyと各設定を確認。apply未実施。EC2交換時の保持とruntime全撤去時の削除の実証はT-102-03で行う。
  - [x] T-102-02 UUID/mountpoint検査と起動条件を実装。完了：volume ID・UUID・ext4・mount先の検査、systemdの起動前検査とmount依存、設定テンプレートを用意。起動処理にformatは含めず、新規volumeの初期化は別途明示的に行う。本人のLinuxコンテナ試験で正常・mount欠落・UUID/volume不一致など11ケースが成功（11 passed / 0 failed）。実EBSとsystemdを組み合わせた検証はT-102-03で行う。
  - [ ] T-102-03 1回のruntime試験でAT-04を実施。完了：実EBSとsystemdでmount欠落・誤volume/UUIDによる起動拒否と空World未生成を確認。正常停止・切離し後、保持したdata EBSを同AZの新EC2へ再接続して同じWorldを確認し、runtimeをdestroyして残置なし。
    進捗（2026-10-03）：異常系3件、World全25ファイルの交換前後一致、EC2交換後の既存World起動を確認済み。本人の実接続・切断、runtime撤去・残置確認が残る。プレイヤーの建築物・所持品の保存試験は未実施で、ファイル一致の確認と混同しない。
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

**次の1手はT-102-03の本人接続確認。その後Codexが正常停止・runtime撤去・残置確認を行う。交換後runtimeは現在稼働・課金中であり、撤去完了扱いにしない。後日、AWS Billing/Cost Explorerに利用料が反映されたら実費を記録する。**
