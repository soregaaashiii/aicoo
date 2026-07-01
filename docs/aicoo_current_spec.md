# AICOO 現状仕様書

最終確認日: 2026-07-01

この文書は、現在のAICOOに実装されている主要機能、画面、正常確認方法を整理した運用仕様です。コード変更、DB変更、設定変更は含みません。

## 1. AICOOの目的

AICOOは、複数Businessを継続的に観測し、改善候補を作り、Ownerが承認できる実行単位へ変換し、実行結果を学習へ戻すための事業改善OSです。

中心エンティティは `Business` です。Idea、LP検証、MVP、Production、Scaling、改善履歴、Google分析、Activity Log、AutoRevisionTaskはBusinessへ集約します。

現在の思想は以下です。

- CEO MODE: 今日どのBusinessを改善すると利益が増えるかを見る
- SYSTEM MODE: 連携、Daily Run、Cron、エラー、設定を直す
- Business詳細: その事業の状態、分析、LP、改善、学習、設定を見る
- Daily Run: 夜間・定期でデータ取得、候補生成、学習、キュー生成を進める
- AutoRevision: 勝手に本番改修せず、Codexへ渡せるPromptと承認待ちタスクを作る

## 2. 主要機能一覧

| 機能 | 目的 | 主なURL | 主なモデル/サービス |
| --- | --- | --- | --- |
| Owner Home / CEO MODE | 今日改善するBusinessを選ぶ | `/owner/focus` | `Aicoo::CeoModeBusinessImprovementBoard`, `Aicoo::AutoRevisionExecutionSummary` |
| Dashboard / SYSTEM MODE | システム状態、Daily Run、Google、Queue、Learningを見る | `/dashboard` | `DashboardSummaryService`, `Aicoo::SystemModeSnapshotBuilder` |
| Business一覧 | 実事業だけを一覧する | `/businesses` | `Business.real_businesses`, `Aicoo::BusinessAnalyticsSummary` |
| Business詳細 | 事業ホーム。Google、LP、Service、改善、Learning、設定を見る | `/businesses/:id` | `Business`, `BusinessMetricDaily`, `ActionCandidate`, `AutoRevisionTask` |
| Business Google設定 | BusinessごとのGA4/GSC/Credential設定 | `/businesses/:id/google_settings` | `BusinessDataSourceSetting`, `AicooGoogleCredential`, `AicooAnalytics::BusinessGoogleApiMetricImporter` |
| Daily Run履歴 | 夜間処理の結果、Step、warning/failedを見る | `/aicoo_daily_runs`, `/aicoo_daily_runs/:id` | `AicooDailyRun`, `AicooDailyRunStep`, `AicooDailyRunner` |
| Cron Health | Render Cron / 手動Daily Runの健康状態を見る | `/admin/cron_health`, `/admin/aicoo_daily_run_health` | `Aicoo::CronHealthDashboard`, `Aicoo::DailyRunHealthSummary` |
| Google連携 | 全体Google CredentialとOAuth復旧 | `/admin/google_credentials` | `AicooGoogleCredential`, `AicooAnalytics::GoogleOauthAuthorization` |
| Google API取得 | Businessを選んでGA4/GSCを非同期取得 | `/admin/google_api_imports` | `GoogleApiImportRun`, `AicooAnalytics::BusinessGoogleApiImportJob` |
| ActionCandidate | 改善候補の一覧・詳細・承認 | `/action_candidates` | `ActionCandidate`, `MetricActionCandidateGenerator`, `AicooInsight::Generator` |
| AutoRevisionTask | Codexへ渡す改修タスク | `/auto_revision_tasks`, `/auto_revision_tasks/codex_queue` | `AutoRevisionTask`, `AicooAutoRevisionQueueBuilderService` |
| Codex Prompt | 改修Promptの確認・export | `/auto_revision_tasks/:id/export_codex_prompt` | `AutoRevisionTask#codex_prompt_markdown`, `Aicoo::CodexPromptComposer` |
| AutoBuildTask | 新規LP/MVP自動Build候補 | `/admin/auto_build_tasks` | `AutoBuildTask`, `Aicoo::ResourceAwareAutoBuilder` |
| Activity Log | 外部サービス・AICOO内の変更履歴 | `/admin/business_activity_logs` | `BusinessActivityLog`, `Aicoo::ActivityIngestor` |
| Activity Learning E2E | Activityが評価・学習へ進めるか診断 | `/admin/activity_learning_e2e_check` | `Aicoo::ActivityLearningE2eCheck`, `ActivityEvaluation` |
| Pipeline E2E | Idea/LP/Business/改修ループの穴を見る | `/admin/pipeline_e2e_check` | `Aicoo::PipelineE2eCheck`, `AicooPipelineRun` |
| Resource Budget | Codex/Build/Deploy/AI予算の状態 | `/admin/aicoo_resource_budget` | `AicooResourceBudget`, `Aicoo::ResourceAwareAutoBuildSummary` |
| SERP設定 | SERP Provider/API Key/テスト検索 | `/admin/serp_settings` | `Aicoo::Serp::Adapter`, `DataSourceCostProfile` |
| 公開LP | 一般公開LP一覧・詳細 | `/`, `/lp`, `/lp/:published_slug` | `AicooLabLandingPage`, `PublicLandingPagesController` |
| LP管理 | 公開LP作成・編集・公開・復旧 | `/admin/aicoo_lab/public_landing_pages` | `AicooLabLandingPage`, `LandingPagePublicationService` |

## 3. Daily Run

### 目的

Daily Runは、AICOOの定期巡回です。Google取得、DataHub収集、BusinessMetricDaily取込、SERP optional step、Activity検知、ActionCandidate生成、Insight生成、ActionResult評価、Learning、AutoBuild、AutoRevision Queueなどを順に実行します。

### 実行方法

- 手動: `/aicoo_daily_runs` から実行
- Render Cron: `bundle exec rails aicoo:daily_run`
- Cron有効化ENV: `AICOO_DAILY_RUN_ENABLED=true`
- JST基準: `TZ=Asia/Tokyo`

### 主なStep

| Step | 役割 | 失敗時の扱い |
| --- | --- | --- |
| `analytics_fetch` | GA4/GSC取得 | OAuth/設定不足はwarning/skipped寄り。致命的な失敗は要確認 |
| `datahub_collect` | Snapshot収集 | 失敗時はDaily Run全体へ影響 |
| `business_metrics_import` | BusinessMetricDaily取込 | 0件ならデータ元確認 |
| `serp_fetch` 等 | SERP依存処理 | SERP未設定ならoptional warning/skipped |
| `source_app_diff_detection` | Source App DB/Git差分検知 | 失敗時はActivity Learningが進まない |
| `action_generation` | ActionCandidate生成 | 0件でも理由をmetadataに残す |
| `insight_generation` | Insight由来候補生成 | 0件でも理由をmetadataに残す |
| `action_result_evaluation` | ActionResult評価 | Learningの入口 |
| `activity_log_evaluation_queue_build` | ActivityEvaluation作成 | Activity Logの評価入口 |
| `score_snapshot` | ActionCandidate順位/補正Snapshot | Learning/Calibration確認用 |
| `owner_execution_queue` | Owner用実行キュー生成 | Owner Homeの導線 |
| `analysis_orchestration` | 分析候補生成 | Data Source/Cost Engine連携 |
| `business_playbook_update` | Business Playbook更新 | 学習の反映 |
| `resource_aware_auto_build` | MVP/AutoBuild候補生成 | Budget OFFならskipped |
| `auto_revision_queue` | AutoRevisionTask生成 | Daily Run成功後だけ実行 |

### 正常条件

- 最新Runが `success` または許容warningつきで内容が進んでいる
- `analytics_fetch_count`, `snapshot_count`, `business_metrics_imported_count` が0ではない、または0の理由がStep metadataにある
- `action_candidates_generated_count` が0でも、`action_generation` stepに理由がある
- AutoRevision QueueをONにしている場合、Daily Run成功後に `auto_revision_queue` stepが出る

### 確認URL

- `/aicoo_daily_runs`
- `/aicoo_daily_runs/:id`
- `/admin/aicoo_daily_run_health`
- `/admin/cron_health`
- `/admin/pipeline_e2e_check`

## 4. Google連携

### 全体設定

全体設定は `/admin/google_credentials` で管理します。AICOO全体で使えるGoogle OAuth Credentialです。

主な役割:

- OAuth Client ID / Secret / Project IDの保存
- Refresh Token / Access Token / Token Expiryの表示
- GA4/GSCまとめて再認証
- GA4再認証
- GSC再認証
- OAuth失敗時の復旧導線

関連モデル:

- `AicooGoogleCredential`
- `AnalyticsSourceSetting`
- `AicooAnalyticsSite`

### Business個別設定

Business個別設定は `/businesses/:id/google_settings` で管理します。

Businessごとに以下を持ちます。

- 使用するGoogle Credential
- GA4 Property ID
- GSC Site URL
- GA4有効/無効
- GSC有効/無効

保存先:

- `BusinessDataSourceSetting` の `source_key: "ga4"` / `"gsc"`
- 補助的に `AicooAnalyticsSite` / `AnalyticsSourceSetting` と同期

取得優先順位:

1. Business個別設定がある場合: Business個別設定を使う
2. Business個別設定がない場合: 全体設定を使う

### 吸えログの設定

現状仕様として、吸えログはBusiness個別設定を使う前提です。

- URL: `/businesses/2/google_settings`
- Business ID: `2`
- GA4 Property ID: `536889590`
- GSC Site URL: 吸えログ用Site URL
- Credential: 吸えログBusinessに設定したGoogle Credential

確認ポイント:

- `/businesses/2/google_settings` にBusiness名「吸えログ」が表示される
- 設定元がBusiness個別設定として表示される
- GA4だけ再取得 / GSCだけ再取得がBusiness個別設定を使う
- 失敗時はGoogle API/OAuthエラー全文が画面に出る

### 再認証・再取得導線

| 操作 | URL |
| --- | --- |
| 全体Google再認証 | `/admin/google_credentials` |
| Business別Google設定 | `/businesses/:id/google_settings` |
| Business別GA4/GSCまとめて再取得 | `/businesses/:id/google_api_import` 相当のボタン |
| GA4だけ再取得 | `/businesses/:id/google_settings` のボタン |
| GSCだけ再取得 | `/businesses/:id/google_settings` のボタン |
| 取得履歴 | `/admin/google_api_imports` |

## 5. Business個別設定

Business詳細・編集・Google設定・Execution Profileが分かれています。

| 設定 | URL | モデル |
| --- | --- | --- |
| 基本情報 / lifecycle / resource status | `/businesses/:id/edit` | `Business` |
| Google GA4/GSC | `/businesses/:id/google_settings` | `BusinessDataSourceSetting` |
| Codex実行先 | `/businesses/:business_id/business_execution_profiles/:id/edit` | `BusinessExecutionProfile` |
| LP / Service | `/businesses/:id` | `AicooLabLandingPage`, `BusinessService` |
| 自動改訂/自動デプロイ | `/businesses/:id/edit`, Execution Profile | `Business`, `BusinessExecutionProfile` |

## 6. ActionCandidate

ActionCandidateはAICOOが作る改善候補です。

主な生成元:

- `MetricActionCandidateGenerator`
- `AicooInsight::Generator`
- Learning Recommendation
- Opportunity / Explore
- 手動作成

主な状態:

- `idea`
- `pending`
- `approved`
- `executor_queued`
- `in_progress`
- `done`
- `rejected`
- `archived`

正常条件:

- `/action_candidates` にBusiness改善候補が出ている
- 候補詳細に期待利益、成功確率、実行プロンプト、評価理由がある
- AutoRevisionTaskへ渡す候補は `execution_prompt` が空でない

異常時:

- Daily Run詳細の `action_generation` step metadataを見る
- `/admin/pipeline_e2e_check` の「ActionCandidate生成」を見る

## 7. AutoRevisionTask

AutoRevisionTaskは、ActionCandidateをCodexへ渡せる改修単位へ変換したものです。

主な状態:

- `draft`
- `waiting_approval`
- `approved`
- `queued`
- `ready_for_codex`
- `sent_to_codex`
- `running`
- `completed`
- `succeeded`
- `partial_succeeded`
- `failed`
- `canceled`

生成ルート:

- ActionCandidate詳細から手動作成
- AutoRevision Queue ON時、Daily Run成功後に自動生成
- Business lifecycle昇格時のMVP/Production/Scaling用タスク
- AutoBuildTaskからの生成

Codex Prompt:

- `/auto_revision_tasks/:id/export_codex_prompt`
- `AutoRevisionTask#codex_prompt_markdown`
- `Aicoo::CodexPromptComposer` により共通ルール・サービス固有ルールを前置き

安全制御:

- high riskは自動merge/deploy禁止
- auto deployはBusiness/Execution Profile設定を参照
- 初期運用ではAutoRevision QueueだけON、自動merge/deployはOFF推奨

## 8. AutoBuildTask / Resource Budget

AutoBuildTaskは、LP反応やLearning Value、Resource Budgetに基づき、MVP生成候補を管理します。

関連URL:

- `/admin/auto_build_tasks`
- `/admin/auto_build_tasks/:id`
- `/admin/aicoo_resource_budget`

関連モデル:

- `AutoBuildTask`
- `AicooResourceBudget`
- `Aicoo::ResourceAwareAutoBuilder`
- `Aicoo::ResourceAwareAutoBuildSummary`

正常条件:

- Resource Budgetが設定されている
- Auto Build ON/OFF、Codex待機数、Build Queue件数、残予算が見える
- Auto Build OFFならDaily Run stepはskippedで正常

## 9. Activity Log

Activity Logは、AICOO自身または外部サービスで発生した変更・作業・施策を学習データとして記録するものです。

入口:

- AICOO内モデルの `AicooActivityTrackable`
- 外部API `POST /api/aicoo/activity_logs`
- Source App diff detection

関連URL:

- `/admin/business_activity_logs`
- `/admin/business_activity_logs/:id`
- `/admin/activity_learning_e2e_check`
- `/admin/source_app_connections`
- `/admin/source_app_diff_rules`

正常条件:

- Shop/Article/LP/ActionResultなど重要変更でBusinessActivityLogが作成される
- ActivityEvaluationがpending/evaluatedへ進む
- source_method `logger` / `db_diff` の状況がE2Eで見える

## 10. Learning

Learningは、予測と実績のズレ、ActionResult、ActivityEvaluation、BusinessPlaybook、Calibrationから改善精度を上げる仕組みです。

関連URL:

- `/owner/learning_report`
- `/admin/aicoo/calibration`
- `/admin/aicoo_judge/action_predictions`
- `/admin/activity_learning_e2e_check`
- `/action_results`

関連モデル/サービス:

- `ActionResult`
- `ActivityEvaluation`
- `ActionCandidateScoreSnapshot`
- `BusinessPlaybook`
- `Aicoo::BusinessPlaybookBuilder`
- `Aicoo::CalibrationEngine`

正常条件:

- ActionResultが登録される
- ActivityEvaluationが作成される
- Daily Runの `score_snapshot`, `business_playbook_update`, `calibration` が動く

## 11. Owner Home

URL: `/owner/focus`

目的:

- 今日おすすめの事業改善TOP10を見る
- 今日の1件を見る
- Businessカードで改善期待値を見る
- 改訂待ち件数を見る
- Daily Run Health要約を見る

正常条件:

- 「今日おすすめの事業改善 TOP10」が表示される
- 「改訂待ち」に承認待ち/実行待ち/失敗/自動デプロイ可否が出る
- システム詳細ログではなく、Business改善中心になっている

異常時:

- Daily Run要確認の場合は `/admin/aicoo_daily_run_health`
- 改訂キュー不明の場合は `/auto_revision_tasks/codex_queue`
- E2E停止点は `/admin/pipeline_e2e_check`

## 12. Dashboard / SYSTEM MODE

URL: `/dashboard`

目的:

- システム状態
- Daily Run / Cron / Queue / Learning / Google / SERP / Resource Budget
- 手動実行ボタン
- Health / Snapshot

正常条件:

- Daily Run Healthが見える
- 実行中Runが分かる
- Google/SERP/Resource/AutoRevisionの状態が確認できる

## 13. Cron

Render CronまたはローカルcronからDaily Runを起動できます。

コマンド:

```bash
bundle exec rails aicoo:daily_run
```

ENV:

```bash
AICOO_DAILY_RUN_ENABLED=true
TZ=Asia/Tokyo
```

仕様:

- ENV未設定ならdisabledとして正常終了
- 手動実行画面はENVに依存しない
- running中は二重起動しない
- 今日成功済みならScheduler側でskip
- 結果は `AicooDailyRun` / `AicooDailyRunStep` に保存

関連docs:

- `docs/render_daily_run.md`
- `docs/local_mac_cron_daily_run.md`

## 14. Resource Budget

Resource Budgetは、AICOOがMVP/AutoBuildを増やす余力を管理する設定です。

管理項目:

- Codex同時実行数
- Codex待機数
- Build Queue件数
- Deploy Queue件数
- Renderサービス数
- 月間AI予算
- 今月使用額
- 残予算
- 同時MVP上限
- Auto Build ON/OFF

正常条件:

- `/admin/aicoo_resource_budget` で状態が見える
- Owner Home / DashboardにBuild Queueや予算要約が出る
- Auto Build OFFなら自動MVP生成は行われない

## 15. 画面一覧

| URL | 何を見る画面か | 正常ならOK | 異常時に見る場所 | 関連モデル/サービス |
| --- | --- | --- | --- | --- |
| `/` | 公開LPトップ | Basic認証なし、LP一覧表示 | `/admin/aicoo_lab/public_landing_pages` | `AicooLabLandingPage` |
| `/lp` | 公開LP一覧 | publishedのみ表示 | sitemap, LP管理 | `PublicLandingPagesController` |
| `/lp/:published_slug` | 公開LP詳細 | 内部文言なし、GA4対象 | LP管理詳細 | `AicooLabLandingPage` |
| `/sitemap.xml` | 公開LP sitemap | XMLでpublished LPのみ | `PublicSitemapsController` | `AicooLabLandingPage.publicly_available` |
| `/robots.txt` | robots | 公開LP index、管理 noindex | `RobotsController` | - |
| `/owner/focus` | 今日の事業改善 | 改善TOP10/改訂待ち/Daily Run要約 | `/admin/pipeline_e2e_check` | `CeoModeBusinessImprovementBoard` |
| `/owner` | Owner Dashboard | 概要が表示 | `/dashboard` | `Aicoo::OwnerFocusHome` |
| `/businesses` | 実事業一覧 | AICOO Analytics Importを除外 | Business scope確認 | `Business.real_businesses` |
| `/businesses/:id` | Businessホーム | Google/LP/改善/Learningが見える | 個別設定/Google設定 | `Business`, `BusinessMetricDaily` |
| `/businesses/:id/edit` | Business基本設定 | lifecycle/resource/auto modes保存 | validation error | `Business` |
| `/businesses/:id/google_settings` | Business別GA4/GSC設定 | 実際に使うProperty/Site/Credentialが見える | `/admin/google_credentials` | `BusinessDataSourceSetting` |
| `/businesses/:id/analytics` | Business Analytics | GSC/GA4/Revenue/Engagementが見える | Google API取得履歴 | `BusinessMetricDaily` |
| `/action_candidates` | 改善候補一覧 | 候補が期待値順に見える | Daily Run action_generation | `ActionCandidate` |
| `/action_candidates/:id` | 改善候補詳細 | 実行Prompt/理由/Execution Guideあり | AutoRevisionTask化 | `ActionCandidate` |
| `/action_results` | 実行結果一覧 | 実績登録/評価状況が見える | Learning Report | `ActionResult` |
| `/auto_revision_tasks` | 改修タスク一覧 | pending/approval/failedが見える | AutoRevision設定 | `AutoRevisionTask` |
| `/auto_revision_tasks/codex_queue` | Codex投入キュー | 実行待ち/実行中/失敗が見える | Task詳細 | `AutoRevisionTask`, `AutoRevisionExecution` |
| `/auto_revision_tasks/:id` | 改修タスク詳細 | Execution Profile/Prompt/結果が見える | Export Prompt | `AutoRevisionTask` |
| `/auto_revision_tasks/:id/export_codex_prompt` | Codex Prompt出力 | 完成Promptが表示 | Codex Rules | `Aicoo::CodexPromptComposer` |
| `/admin/codex_prompt_rules` | Codex共通/事業別ルール管理 | active/priority/content確認 | preview | `CodexPromptRule` |
| `/admin/codex_prompt_rules/preview` | Prompt Preview | Business別Promptを確認 | rules編集 | `CodexPromptRule` |
| `/aicoo_daily_runs` | Daily Run一覧 | 直近Run statusが見える | Run詳細 | `AicooDailyRun` |
| `/aicoo_daily_runs/:id` | Daily Run詳細 | Step Timeline/summary/errorが見える | Step再実行 | `AicooDailyRunStep` |
| `/admin/cron_health` | Cron Health | 最終成功/失敗/今日回数が見える | Daily Run詳細 | `Aicoo::CronHealthDashboard` |
| `/admin/aicoo_daily_run_health` | Daily Run Health | running/stuck/retry/step状態が見える | Run詳細 | `Aicoo::DailyRunHealthSummary` |
| `/admin/google_credentials` | Google全体連携復旧 | connected/expired/invalidが見える | OAuthログ/Business設定 | `AicooGoogleCredential` |
| `/admin/google_api_imports` | Google API取得 | Business別Run履歴が見える | Business google_settings | `GoogleApiImportRun` |
| `/admin/analytics_sites` | Analytics Site管理 | GA4/GSC site/property一覧 | Google credentials | `AicooAnalyticsSite` |
| `/admin/pipeline_e2e_check` | Pipeline/改修ループE2E | pass/warning/failと停止点が見える | 各関連画面 | `Aicoo::PipelineE2eCheck` |
| `/admin/activity_learning_e2e_check` | Activity Learning E2E | Activity検知から評価まで診断 | Source App設定 | `Aicoo::ActivityLearningE2eCheck` |
| `/admin/business_activity_logs` | Activity Log一覧 | 変更ログがある | API/SourceApp/Logger | `BusinessActivityLog` |
| `/admin/source_app_connections` | Source App接続 | active connectionがある | Diff Rules | `SourceAppConnection` |
| `/admin/source_app_diff_rules` | DB/Git差分ルール | active ruleがある | E2E Check | `SourceAppDiffRule` |
| `/admin/auto_build_tasks` | AutoBuildTask一覧 | pending/building/completedが見える | Resource Budget | `AutoBuildTask` |
| `/admin/aicoo_resource_budget` | Resource Budget | 残予算/Queue/ON/OFFが見える | AutoBuildTask | `AicooResourceBudget` |
| `/admin/serp_settings` | SERP設定 | Provider/API Key/テスト検索 | Optional warning | `Aicoo::Serp::Adapter` |
| `/admin/idea_pipeline` | Idea Pipeline | Idea/Score/SERP/LP/MVP状態が見える | Pipeline E2E | `IdeaPipelineItem`, `AicooPipelineRun` |
| `/admin/aicoo_lab/public_landing_pages` | 公開LP管理 | draft/published/paused管理 | sitemap/LP詳細 | `AicooLabLandingPage` |
| `/admin/aicoo_datahub` | DataHub | Snapshot収集状態 | Daily Run詳細 | `AicooDataHub::DailyCollector` |
| `/admin/aicoo/calibration` | Calibration | 補正状態/承認 | Judge | `Aicoo::CalibrationEngine` |
| `/admin/aicoo_judge/action_predictions` | 予測と実績 | 誤差/精度が見える | ActionResult | `ActionPredictionCalibrationImpact` |

## 16. 現在の懸念

| 領域 | 懸念 |
| --- | --- |
| Google連携 | 全体設定とBusiness個別設定が併存しているため、実際に使う設定元の表示確認が重要 |
| AutoRevision | QueueがOFFだとDaily Run後にAutoRevisionTaskが自動生成されない |
| Business auto_revision_mode | `manual` だとAutoRevisionTaskがdraft提案になり、Owner承認待ちに出にくい |
| Daily Run | `partial_failed` だとAutoRevision Queueが走らない設計 |
| Activity Log | 外部サービス側Logger/API送信が止まるとActivity Learningが0件になる |
| AutoBuild | Resource Budget OFFなら正常にskipped。自動MVP生成とは別に明示確認が必要 |
| 自動deploy | 安全のためOFF推奨。新規LP/Lab限定ポリシーのみ別途確認 |

