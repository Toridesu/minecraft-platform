# Production Minecraft Platform — TODO v2.0

## 現在の状況
本日の終了記録（2026-10-03、20:15 JST照会開始）：T-103-01完了で終了し、02は未着手。T-103ではapplyしていない。東京リージョンを読み取り専用で再確認し、EC2（停止中を含む）、EBS、自己所有snapshot、EIP/ENI、NAT、VPC Endpoint、ELB、RDS本体/手動snapshot、EFS、ECS cluster、ECR repository、Backup vault、Secrets Manager、Lambda、CloudWatch alarmは該当なし。runtime stateは空。S3はBootstrap state bucketのみで、全44 version合計387,150 bytes（約378 KiB、STANDARD）、delete marker 29件、未完了multipartなし。state保管料・リクエスト料は残る。KMSはAWS管理キー4件のみで、専用customer-managed keyなし。別project由来のCloudWatch log groupは1件、storedBytes=0・保持1日で変更せず保持。Route 53 hosted zoneも該当なし。照会範囲内で本projectのruntime継続課金資源は見つからないが、他リージョン・契約課金・全AWSサービス・実請求は未確認。証跡はGit外の`evidence/end-of-day-20261003/`へ保存。次回はT-103-02の設計意図と学習/反復作業の分担説明から再開する。

現在：**T-004-01〜10、T-005-01〜05、T-006、T-101-01〜06完了。費用基準は月10 USD、1回1 USDを目標、1回の見込みが2 USD以上なら新規作成を中止と承認済み。2026-09-29のsession-runtime applyは14 add / 0 change / 0 destroy、destroyは14 destroyed。Minecraft Java 26.1をMicrosoft OpenJDK 25.0.4.1で起動し、配布物のSHA検証、EULA同意、非rootユーザー・systemd起動停止を確認。本人クライアントから接続し、ログイン・切断を確認。SIGTERM由来の終了コード143はsystemdで成功扱いとなり、サービスは`inactive (dead)`。session-runtime stateは空。EC2/EBS/Public IPv4、VPC/Endpoint等ネットワーク、Minecraft専用IAMはサービス別照会で該当なし。BootstrapのS3 bucketとstate objectは存在し、Bootstrap stateの管理資源一覧も確認。`ExpiresAt`タグの日時を過ぎてもEC2は自動停止しなかったため、タグは自動cleanupではないと実証。90分の約$0.21は事前見積りで実費ではない。実際の請求額はAWS Billing/Cost Explorer反映後に確認する。Bootstrapは通常保持し、完全終了は別手順とする。**
2026-10-03：T-102-01完了。独立した暗号化gp3 16 GiBのdata EBSとattachmentを追加し、既存のAWS管理キーを参照。本人がfmt/validate、実行先・default workspace・空のruntime stateを確認し、Plan 16 add / 0 change / 0 destroyを確認後、16 resourceのapplyを完了。
T-102完了（2026-10-03）：Linuxコンテナの模擬試験11件に加え、実systemdでUUID不一致・volume ID不一致・mount不可による起動拒否、Java未起動・空World未生成を確認。正常起動・停止後のWorld全25ファイルのSHA-256を記録し、unmount後にEC2とattachmentのみ交換（2 add / 0 change / 2 destroy）。同じdata EBS・UUIDをformatせず再利用し、起動前の全25ファイル一致と既存World読み込み、交換後EC2への本人接続・切断を確認。本人の明示依頼により後半のAWS操作・撤去はCodexが実施。
撤去完了：保存済みdestroy Plan（0 add / 0 change / 16 destroy）を適用し、16件を削除。Minecraft停止は`inactive`・`Result=success`・MainPID=0。runtime stateは空。交換前後root EBS・data EBS、稼働中等の対象EC2、Public IPv4の割当先ENI、VPC/Endpoint/Subnet/Route Table/SG/IGW、専用IAMの残置なしをサービス別に確認。BootstrapのS3 bucketとstate objectは保持。証跡はGit対象外の`evidence/`に保存。プレイヤーの建築物・所持品の交換前後比較は未実施であり、Worldファイル一致と区別する。
T-103-01完了（2026-10-03）：本人がS3保護設定、HTTPS強制bucket policy、EC2の限定IAM Policyを記述し、Versioning/LifecycleとPlanの管理境界・権限範囲・仮ARNを理解したことを確認。両rootのfmt/validate・TFLint、公開対象ソースのsecret検査、全infraのTrivy検査に成功。既存networkのAWS-0104/0164は本人承認により該当2箇所のみ理由・見直し期限（2026-12-31、常設化/重要データ導入時は前倒し）付き例外とし、AWS通信設定は変更しない。CIにsession-dataを追加。確認用Planはsession-data 7 add、backup ARN指定runtime 17 add、未指定16 add（すべて0 change/0 destroy）。これらの仮ARN・確認専用入力のPlanはapply禁止で、03前に実bucket ARN・新RunId/期限で再Planする。S3追加費用は容量/全version/requests等の従量課金、専用KMS等の固定月額資源は追加しない。03全体の見積りは作成直前に再確認。applyは行わずAWS資源は作成していない。証跡はGit外のevidence/。BootstrapのS3保存料・リクエスト料は残る。

GitHub静的CIも成功：`Terraform Static Checks` run `37117089186`（Git SHA `c1bf370`）。Bootstrap/runtime/session-dataのfmt/validate/TFLint、infra設定scan、secret scanを検証。AWS認証・Plan/apply/destroyは行わないWorkflowで確認した。

## 進め方

1回のAWS作業を「作成→確認→証跡→撤去」で閉じる。タスクをまたいでAWSを放置せず、必要なら次回再applyする。依存は学習・コードの準備順であり、前タスクの資源を常設する意味ではない。
チェックは実測と証跡が揃ってから付ける。旧版のタスク番号/完了条件は本一覧で置き換える。非公開の設計資料にあるラボ一覧・受入試験・撤去手順も参照する。

### サブタスクの進め方

- 目的は学習。Codexが一気に実行するのではなく、本人が理解しながら自分で進められるよう案内する。
- 基本の順序は「設計意図を説明→本人が理解したことを確認→今回初めて行うこと・学習として本人が行う価値のあることを切り分け→担当を合意→実施」。本人から質問されるのを待たず、Codexからこの切り分けを提示する。
- サブタスク開始時は、設計意図・学習部分の説明に加え、完了までの作業の流れを担当付きの番号付き一覧で示す。表記は「1. ○○（ChatGPT）」「2. ○○（あなた）」とし、本人の担当を「私」と表記しない。この一覧は作業順と分担を示すもので、新しいサブタスク番号は増やさない。
- 初回かどうかは本人の作業履歴で判断し、同じ操作を別root/フォルダへ適用するだけなら原則反復としてCodexが担当する。新しい管理境界や判断は説明するが、理解できていれば準備操作まで本人に繰り返させない。学習部分は手順の丸写しではなく、設定・判断とその結果の理解を中心にする。
- 初めて使うコマンド・操作や、新しい概念・学習上重要な判断を含む作業は、意味・目的・影響・期待結果を説明した後、本人が実行する。理解済みのコマンドでも用途やリスクが新しければ、新しい学習として扱う。
- 理解済みの反復操作・確認・記録はCodexが担当する。担当する範囲と結果を簡潔に共有し、学習する必要がある初回操作まで一括実行しない。削除対象・課金・権限などの範囲を広げる場合は、別途本人の判断を求める。
- 同じ確認を再実施する場合は、必要性、前回から変わった条件、今回分かることを先に説明する。例：EC2交換後のUUID確認は新EC2が正しいEBSを接続している証明、模擬試験後の実systemd試験は本番経路の検証。学習上必要なら本人が実施し、単純な再確認はCodexがまとめて行う。
- 手順は意味のある作業単位にまとめる。初回・安全上重要な操作は段階的に進めるが、理解済みの各コマンドごとに報告を求める進め方は避ける。サブタスク開始時に「本人が学ぶ部分」と「Codexが担当する反復部分」を示す。
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
- [x] T-102 独立data EBS、mount検査、EC2交換を実装。完了：実systemdの異常系3件で起動拒否・空World未生成を確認。同じdata EBSをformatせず新EC2へ再接続し、World全25ファイルの一致、既存World起動と本人接続・切断を確認。runtime16件を撤去し、state空・サービス別残置なし、Bootstrap保持を確認。全サブタスク完了のため子行を削除。依存：T-101。試験：AT-04。
- [ ] T-103 session-dataのS3と整合backup/restoreを実装。完了：runtimeを壊しても新EBSに戻せる。依存：T-102。試験：AT-06、AT-07。
  - [x] T-103-01 backup S3・権限・state分離を準備する。完了：session-data/backend、S3 Standard・SSE-S3・Versioning・公開遮断・HTTPS強制・Lifecycle、bucket/prefix限定のEC2 IAMを用意。fmt/validate・lint/scan成功、Planのdata 7 add/runtime 17 add（権限なし16）・保持/撤去境界・費用区分を確認し、本人が理解。networkの限定例外は本人承認・理由/期限付き。apply未実施。実backup/restoreは02〜03で検証する。
    担当：本人は新しいS3の保護/保持設定とIAM Policyを説明後に記述し、Planの該当部分を確認する。Codexは反復であるsession-data雛形/backend準備・初期化、静的確認・差分整理・記録・Git反映を担当。runtime撤去対象にbackup S3が含まれない管理境界は一緒に確認する。
  - [ ] T-103-02 backup/restore処理とローカル試験を用意する。学習：停止済みの整合点、checksum/manifest、復元前検証、失敗時に成功扱いしない仕組み。作業：固定SSM Documentと共通flock、正常停止・保存/process終了確認→staging→archive/SHA-256/manifest→一意keyへupload、指定backupを検証して正しい空のmount先にrestoreする処理を用意。秘密を除外し、復元に必要な設定/版は残す。完了：正常系、停止/upload失敗、checksum不一致のローカル試験が通る。実S3/systemdでの成立は03で確認し、ローカル成功だけで整合backup完了としない。
    担当：本人はflock・archive・manifest・restoreの初回操作と重要な実装を説明後に実施。Codexは理解済みの試験繰返し・確認・記録・Git反映を担当。
  - [ ] T-103-03 S3からの復旧を実証し、全演習資源を撤去する。学習：元EBS消失からの復旧、復旧点と失われる変更、S3全versionの削除。作業：session-data/runtimeを作成し、本人がWorldの目印・所持品を用意→整合backupを取得し読めることを確認→backup後の変更を追加→runtimeのみ全撤去→新EC2/新EBSへS3からrestore→本人接続で復旧点のWorld/所持品・dimensionデータと変更差分を確認。時刻とRPO/RTOを記録。完了：AT-06/07の証跡を保存し、runtime、backupの全version/delete marker、session-dataを撤去してサービス別残置なし。Bootstrapは保持。新規作成前に費用基準を確認し、失敗時も未達結果を記録して撤去する。
    担当：本人は初回のS3転送/復元、復旧点の選択、ゲーム内確認、version指定削除を説明後に実施。Codexは理解済みのapply/destroy・再配置・残置確認・記録・Git反映を担当。再確認の必要性は先に説明する。
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

**今日はT-103-01完了で終了。終了時の残置確認済みで、runtimeは撤去状態・state空。残る保管料はBootstrap S3等の上記範囲を参照。次回はT-103-02の設計意図・新しい学習部分の説明と担当分けから。確認用の仮ARN Planはapplyしない。**
