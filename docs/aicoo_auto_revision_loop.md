# AICOO 自動改修ループ 現状仕様

最終確認日: 2026-07-01

この文書は、AICOOの自動改修ループが現在どこまで実装されているか、どこで止まりやすいか、何をONにして何を手動のままにするべきかを整理します。

## 1. 対象フロー

```text
Render Cron
↓
Daily Run
↓
GA4/GSC取得
↓
ActionCandidate生成
↓
AutoRevisionTask生成
↓
Codex Prompt生成
↓
Owner承認
↓
Activity Log / ActionResult
↓
Learning
```

## 2. 現在地

現在、以下は実装済みです。

- Render CronからDaily Runを起動するRake Task
- Daily Run履歴とStep保存
- GA4/GSC取得JobとBusinessMetricDaily保存
- SERP Optional Mode
- ActionCandidate生成
- ActionCandidate生成0件時の理由metadata
- AutoRevision Queue設定
- ActionCandidateからAutoRevisionTask生成
- Codex Prompt生成/Export
- Owner Homeの改訂待ちカード
- AutoRevisionExecution記録
- ActionResult登録
- Activity Log受信API
- ActivityEvaluation作成
- BusinessPlaybook / Calibration / Score Snapshot
- Pipeline E2E診断
- 自動改修ループE2E診断

まだ完全自動ではありません。

- Codexが実際にコードを書いてGitHub PRを作る部分は、AICOO内ではPrompt/状態管理までが中心
- 自動merge/deployは安全のためOFF運用が前提
- high riskはPrompt確認まで
- 実行後のActionResult/Activity Log登録は、外部作業またはLogger/API連携が必要

## 3. ステップ別仕様

| Step | 実装済み | ON/OFF設定 | 確認URL | 正常条件 | よくある停止理由 | 次に直すべき点 |
| --- | --- | --- | --- | --- | --- | --- |
| Render Cron | 済 | `AICOO_DAILY_RUN_ENABLED=true` | `/admin/cron_health` | 今日successあり | ENV false、Cron未設定、Render Job失敗 | Cron Healthで原因を画面完結表示 |
| Daily Run | 済 | Daily Run Setting | `/aicoo_daily_runs` | 最新Run success | running/stuck/partial_failed | partialでもQueue可能にするか判定整理 |
| GA4/GSC取得 | 済 | Business個別/全体Google設定 | `/businesses/:id/google_settings`, `/admin/google_api_imports` | AnalyticsFetchRun success、BusinessMetricDaily更新 | token失効、Property/Site不一致、権限不足 | Business別設定の実使用値を常に明示 |
| ActionCandidate生成 | 済 | 生成ロジック内 | `/action_candidates`, `/aicoo_daily_runs/:id` | 1件以上、または0件理由あり | 指標不足、閾値未達、Business対象外 | 低データ時でもルール候補を厚くする |
| AutoRevision Queue | 済 | `/admin/aicoo_auto_revision_settings` | `/admin/pipeline_e2e_check` | Queue ON、Daily Run成功後に実行 | Queue OFF、Daily Run partial_failed、候補にPromptなし | partial_success時の安全実行可否検討 |
| AutoRevisionTask生成 | 済 | Queue設定/Business auto_revision_mode | `/auto_revision_tasks` | Task作成、status適切 | active task重複、score不足、manualでdraft | Owner承認待ちへ出すBusinessをapproval化 |
| Codex Prompt生成 | 済 | CodexPromptRule / Execution Profile | `/auto_revision_tasks/:id/export_codex_prompt` | 完成Prompt表示 | Execution Profile不足、Prompt空 | Prompt品質と対象Repoの検証強化 |
| Owner承認 | 済 | Business auto_revision_mode | `/owner/focus`, `/auto_revision_tasks` | waiting_approval表示 | manualなのでdraft、high risk | 承認待ちUIの優先順位改善 |
| Codex実行管理 | 半自動 | AutoRevisionTask status | `/auto_revision_tasks/codex_queue` | queued/running/completed管理 | 実際のGitHub PR作成は手動寄り | GitHub PR作成API連携 |
| Activity Log | 済 | API token / SourceApp設定 | `/admin/business_activity_logs` | 作業後Activity作成 | 外部Logger未発火、token不一致、business未解決 | 外部サービスごとの送信ログ監視 |
| ActionResult | 済 | 手動/結果取込 | `/action_results` | 実績が候補に紐付く | 登録漏れ | AutoRevision完了時の結果登録導線強化 |
| Learning | 済 | Daily Run step | `/owner/learning_report`, `/admin/activity_learning_e2e_check` | 評価/補正/Playbook更新 | Activity/Result不足 | ActionResultとActivityEvaluationの自動紐付け精度 |

## 4. 詳細フロー

### 4.1 Render Cron

起動コマンド:

```bash
bundle exec rails aicoo:daily_run
```

Cron用ENV:

```bash
AICOO_DAILY_RUN_ENABLED=true
TZ=Asia/Tokyo
```

確認:

- `/admin/cron_health`
- `/admin/aicoo_daily_run_health`
- `/aicoo_daily_runs`

正常:

- 最終Cron開始/終了が今日
- 今日成功回数が1以上
- latest run statusが `success`

停止理由:

- ENV未設定でdisabled
- Render Cron Job未設定
- runningが長時間続く
- failed/partial_failed

### 4.2 Daily Run

実装:

- `AicooDailyRunner`
- `AicooDailyRunScheduler`
- `AicooDailyRun`
- `AicooDailyRunStep`

確認:

- `/aicoo_daily_runs/:id`

正常:

- Step Timelineが出る
- failedがない
- warning/skippedに理由がある

重要:

AutoRevision Queueは現在、Daily Runが `success` の場合だけ `run_auto_revision_queue!` で呼ばれます。`partial_failed` では止まる可能性があります。

### 4.3 GA4/GSC取得

実装:

- `AicooAnalytics::DailyFetchJob`
- `AicooAnalytics::BusinessGoogleApiImportJob`
- `AicooAnalytics::BusinessGoogleApiMetricImporter`
- `GoogleApiImportRun`
- `AnalyticsFetchRun`

設定:

- 全体: `/admin/google_credentials`
- Business個別: `/businesses/:id/google_settings`

正常:

- GA4/GSCのFetch Runがsuccess
- `BusinessMetricDaily` にsessions/pageviews/clicks/impressions等が保存

停止理由:

- OAuth token expired / invalid_grant
- Google Credential不一致
- GA4 Property ID不一致
- GSC Site URL不一致
- 権限不足
- API metric名不正

### 4.4 ActionCandidate生成

実装:

- `MetricActionCandidateGenerator`
- `AicooInsight::Generator`
- `CorrectionReadinessActionCandidateGenerator`
- `ActionCandidate`

確認:

- `/action_candidates`
- Daily Run詳細の `action_generation`

正常:

- 1件以上作成
- 0件ならmetadataに理由が出る

停止理由:

- Business対象外
- 指標不足
- 比較対象不足
- 閾値未達
- 既存候補あり
- `execution_prompt` が空

### 4.5 AutoRevisionTask生成

実装:

- `AicooAutoRevisionDailyRunQueuer`
- `AicooAutoRevisionQueueBuilderService`
- `Aicoo::BusinessAutoRevisionRouter`
- `AutoRevisionTask`
- `AutoRevisionQueueRun`
- `AutoRevisionRunLog`

ON/OFF:

- `/admin/aicoo_auto_revision_settings`
- `AicooAutoRevisionSetting.enabled`

対象候補:

- `ActionCandidate.active_for_ranking`
- status: `idea`, `pending`, `approved`
- `execution_prompt` あり
- final_scoreがminimum以上
- activeなAutoRevisionTaskが未作成

Businessモード:

| `auto_revision_mode` | 動き |
| --- | --- |
| `manual` | draft提案のみ |
| `approval` | waiting_approvalへ追加 |
| `automatic` | low riskのみCodex送信準備。ただしDeployは承認制 |

停止理由:

- Queue OFF
- Daily Runがsuccessでない
- 候補0件
- score不足
- active task重複
- high risk
- Business mode manualでdraft止まり

### 4.6 Codex Prompt生成

実装:

- `AutoRevisionTask#codex_prompt_markdown`
- `AutoRevisionTask#codex_prompt`
- `Aicoo::CodexPromptComposer`
- `CodexPromptRule`
- `BusinessExecutionProfile`

確認:

- `/auto_revision_tasks/:id/export_codex_prompt`
- `/admin/codex_prompt_rules/preview`

Promptに含まれるもの:

- 共通ルール
- サービス固有ルール
- Business
- GitHub Repository
- Branch
- Execution Profile
- auto deploy可否
- high risk禁止事項
- test/lint/deploy command
- 完了報告フォーマット

停止理由:

- AutoRevisionTaskなし
- Business Execution Profile不足
- Prompt対象が不明
- high riskで自動不可

### 4.7 Owner承認

確認:

- `/owner/focus`
- `/auto_revision_tasks`
- `/auto_revision_tasks/codex_queue`

正常:

- waiting_approvalがOwner Homeに出る
- 承認後にready_for_codex/queuedへ進む

停止理由:

- Business modeがmanual
- Task statusがdraft
- high risk
- Prompt target validationエラー

### 4.8 Codex実行・PR・Deploy

現在の実装範囲:

- Codex Prompt表示
- Task status管理
- AutoRevisionExecution保存
- 結果登録
- deploy metadata保存
- rollback requested記録

まだ手動寄り:

- 実際のCodex実行
- GitHub branch/commit/push/PR作成
- Render deploy確認

安全方針:

- 自動merge OFF
- 自動deploy OFF
- high riskは自動不可
- production/収益Businessは承認制

### 4.9 Activity Log / ActionResult

実装:

- `ActionResult`
- `BusinessActivityLog`
- `Aicoo::ActivityIngestor`
- `POST /api/aicoo/activity_logs`
- `AicooActivityTrackable`
- `AicooActivityLogger`

正常:

- 実行後にActionResultが登録される
- 外部サービス変更がActivity Logになる
- ActivityEvaluationが作成される

停止理由:

- 実行結果未登録
- 外部Logger未発火
- API token不一致
- business_key不一致
- Business紐付け不可

### 4.10 Learning

実装:

- `ActionResultEvaluator`
- `Aicoo::ActivityEvaluationBuilder`
- `Aicoo::BusinessPlaybookBuilder`
- `ActionCandidateScoreSnapshotter`
- `Aicoo::CalibrationEngine`

確認:

- `/owner/learning_report`
- `/admin/activity_learning_e2e_check`
- `/admin/aicoo/calibration`
- `/admin/aicoo_judge/action_predictions`

正常:

- ActionResultやActivityEvaluationが評価される
- Score Snapshotが作成される
- BusinessPlaybookが更新される

## 5. 機能ヘルスチェック表

| 機能名 | 状態 | 確認URL | 正常条件 | 現在の懸念 | 優先度 |
| --- | --- | --- | --- | --- | --- |
| Render Cron | 実装済み | `/admin/cron_health` | 今日successあり | Render側設定依存 | 高 |
| Daily Run | 実装済み | `/aicoo_daily_runs` | latest success | partial_failed時にQueue停止 | 高 |
| GA4/GSC | 実装済み | `/businesses/:id/google_settings` | BusinessMetricDaily更新 | 全体/個別設定の混乱 | 高 |
| ActionCandidate | 実装済み | `/action_candidates` | 候補1件以上 | 低データ時0件リスク | 高 |
| AutoRevision Queue | 実装済み | `/admin/aicoo_auto_revision_settings` | enabled true | OFFだとTask生成なし | 高 |
| AutoRevisionTask | 実装済み | `/auto_revision_tasks` | Task生成 | manualだとdraft止まり | 高 |
| Codex Prompt | 実装済み | `/auto_revision_tasks/:id/export_codex_prompt` | Prompt表示 | Execution Profile不足 | 高 |
| Owner承認 | 実装済み | `/owner/focus` | waiting_approval表示 | draftは目立ちにくい | 中 |
| GitHub PR自動作成 | 土台のみ | `/auto_revision_tasks/codex_queue` | PR URL保存 | 完全自動は未完成 | 中 |
| Render Deploy自動確認 | 土台のみ | AutoRevisionTask詳細 | deploy_status保存 | 自動deployはOFF推奨 | 中 |
| Activity Log | 実装済み | `/admin/business_activity_logs` | Activity増加 | 外部Logger依存 | 高 |
| Activity Learning | 実装済み | `/admin/activity_learning_e2e_check` | Evaluation作成 | Activity 0件だと止まる | 中 |
| Learning/Calibration | 実装済み | `/owner/learning_report` | 補正/学習更新 | 実績データ不足 | 中 |
| AutoBuild | 実装済み | `/admin/auto_build_tasks` | Budgetに応じてTask | OFFならskipped | 中 |
| Resource Budget | 実装済み | `/admin/aicoo_resource_budget` | 残予算/Queue表示 | 運用ルールが必要 | 中 |
| SERP Optional | 実装済み | `/admin/serp_settings` | 未設定でもDaily Run継続 | SEO精度低下 | 低 |

## 6. 自動改修ループの正常条件

Daily Run後、最低限以下が満たされると「自動改修ループが回っている」と判断します。

1. `/aicoo_daily_runs/:id` が `success`
2. `analytics_fetch` がsuccessまたは許容warning
3. `action_generation` が候補を作る、または0件理由が明確
4. `/action_candidates` に候補がある
5. AutoRevision QueueがON
6. `/auto_revision_tasks` にTaskが作成される
7. `/auto_revision_tasks/:id/export_codex_prompt` が表示できる
8. `/owner/focus` に承認待ち改修が表示される
9. 実行後にActionResultまたはActivity Logが記録される
10. Learning / Calibrationに評価データが入る

## 7. ONにすべき設定

| 設定 | 推奨 | 理由 |
| --- | --- | --- |
| AutoRevision Queue | ON | Daily Run後にAutoRevisionTaskを作るため |
| Business auto_revision_mode | `approval` | Owner承認待ちに出すため |
| Resource Budget Auto Build | 必要なLabのみON | 新規LP/MVP検証向け |

## 8. まだ手動にしておく設定

| 設定 | 推奨 | 理由 |
| --- | --- | --- |
| auto merge | OFF | PR内容確認が必要 |
| auto deploy | OFF | 本番影響を避ける |
| high risk自動実行 | OFF | DB/認証/課金/Daily Run等の事故防止 |
| 既存収益Businessの自動deploy | OFF | 収益導線破壊を避ける |

## 9. 今足りないもの

### 仕様面

- Businessごとの「どこまで自動化するか」の運用基準
- production/scaling Businessの自動改修禁止範囲
- high/medium/low riskの実例集

### UI導線

- AutoRevision Queue OFF時のOwner Home上の明確な誘導
- draft提案とwaiting_approvalの差が分かりにくい
- Codex実行後の結果登録導線をもっと目立たせる余地

### 自動改修ループ

- `partial_failed` でも安全なstepだけAutoRevision Queueへ進めるかの設計
- GitHub PR作成の完全連携
- PR URL / commit SHA / deploy URLの自動保存

### 学習ループ

- Activity LogとActionCandidate/ActionResultの自動紐付け強化
- 外部サービスActivity Loggerの送信失敗監視
- 実行時間や作業粒度の精度向上

### Google連携

- 全体設定とBusiness個別設定の使用元表示を全画面で統一
- Business別GA4/GSCテスト取得の結果表示をさらに明確化

### 新規LP自動Build

- AutoBuild ON対象をLab Businessに限定する運用UI
- 自動Build後のPR/Deploy/計測確認の標準手順

## 10. 次にやるべき改修TOP5

1. AutoRevision Queue ON/OFFとBusiness `auto_revision_mode` をOwner Homeから一目で分かるようにする
2. Daily Run `partial_failed` でも安全な場合はAutoRevision Queueを実行できる判定を追加する
3. AutoRevisionTask完了後にActionResult/Activity Log登録へ誘導する専用画面を作る
4. GitHub PR作成/PR URL保存までをAICOO管理画面から実行できるようにする
5. Business別Google設定の「実際に使われた設定元・Credential・Property・Site」をDaily Run詳細にも表示する

