# AICOO 運用チェックリスト

最終確認日: 2026-07-01

この文書は、管理者が毎朝AICOOを見る順番と、異常時の確認先をまとめたものです。

## 毎朝見る順番

### 1. Owner Homeを見る

URL: `/owner/focus`

見るもの:

- 今日の1件
- 今日おすすめの事業改善TOP10
- 改訂待ち
- Daily Run Health要約
- Businessカード

正常条件:

- Business改善候補が表示される
- 「改訂待ち」に承認待ち/実行待ち/失敗数が出る
- Daily Runが正常またはwarning理由が明確

異常時:

- 改善候補が0件: `/aicoo_daily_runs/:id` の `action_generation`
- 改訂待ちが0件: `/admin/pipeline_e2e_check`
- Daily Run異常: `/admin/aicoo_daily_run_health`

## 2. Daily Run結果を見る

URL:

- `/aicoo_daily_runs`
- `/aicoo_daily_runs/:id`

見るもの:

- 最新Runのstatus
- sourceが `cron` か `manual` か
- 実行時間
- failed/warning/skipped step
- `action_generation`
- `auto_revision_queue`

正常条件:

- statusが `success`
- `analytics_fetch`, `business_metrics_import`, `action_generation` が実行済み
- `action_generation` が0件の場合も理由がmetadataにある
- AutoRevision Queue ON時は `auto_revision_queue` stepがある

異常時:

- `partial_failed`: failed stepを確認。AutoRevision Queueは成功Run後だけなので止まる可能性あり
- `analytics_fetch` failed: `/admin/google_credentials` または `/businesses/:id/google_settings`
- `source_app_diff_detection` failed: `/admin/activity_learning_e2e_check`
- メモリ懸念: Step metadataの `memory_start`, `memory_finish`, `memory_delta_mb`

## 3. Cron Healthを見る

URL:

- `/admin/cron_health`
- `/admin/aicoo_daily_run_health`

見るもの:

- 最終Cron開始/終了
- 最終成功
- 今日の実行回数
- 今日の成功/失敗/skip数
- runningが30分以上続いていないか
- stuck/retry

正常条件:

- 今日1回以上success
- running長時間なし
- failed率が高くない

異常時:

- Cron disabled: Render Cron ENV `AICOO_DAILY_RUN_ENABLED=true` を確認
- 今日成功なし: Render Cron Job設定とDaily Run詳細を確認
- running長時間: `/aicoo_daily_runs/:id`

## 4. 自動改修ループE2Eを見る

URL: `/admin/pipeline_e2e_check`

見るもの:

- Render Cron / Daily Run
- GA4/GSC取得
- ActionCandidate生成
- AutoRevision Queue設定
- AutoRevisionTask生成
- Codex Prompt生成
- Owner承認待ち
- Activity Log / ActionResult
- Learning

正常条件:

- すべてpass、またはwarning理由が明確
- 停止点が表示されている

異常時:

- AutoRevision Queue OFF: `/admin/aicoo_auto_revision_settings`
- AutoRevisionTask 0件: ActionCandidateに `execution_prompt` があるか確認
- Codex Prompt空: AutoRevisionTask詳細を確認
- Owner承認待ち0件: Business `auto_revision_mode` がmanualの可能性

## 5. ActionCandidateを見る

URL: `/action_candidates`

見るもの:

- 新規候補が作成されているか
- Businessが実事業か
- 期待利益/成功確率/評価理由
- 実行プロンプト

正常条件:

- 候補がある
- `execution_prompt` がある
- 不要なAICOO Analytics Importが出ない

異常時:

- 候補0件: Daily Run `action_generation` metadataを見る
- 抽象的すぎる: Action Expansion / Execution Guideを確認
- AutoRevisionTask化されない: `execution_prompt`, final_score, status, 既存active taskを確認

## 6. AutoRevisionTaskを見る

URL:

- `/auto_revision_tasks`
- `/auto_revision_tasks/codex_queue`
- `/auto_revision_tasks/:id/export_codex_prompt`

見るもの:

- 承認待ち
- 実行待ち
- 失敗
- high risk
- Codex Prompt
- Execution Profile

正常条件:

- Daily Run後にTaskが増える
- Promptが確認できる
- high riskは自動実行されない
- auto merge/deployはOFFのまま

異常時:

- Task 0件: `/admin/aicoo_auto_revision_settings`, `/admin/pipeline_e2e_check`
- Promptに対象Repoがない: Business Execution Profile
- failed: AutoRevisionTask詳細とExecution詳細

## 7. Activity Logを見る

URL:

- `/admin/business_activity_logs`
- `/admin/activity_learning_e2e_check`

見るもの:

- 今日検知したActivity
- 評価待ちActivity
- source_method `logger`
- source_method `db_diff`
- ActivityEvaluation件数

正常条件:

- 外部サービスで作業するとActivity Logが増える
- ActivityEvaluationが作成される
- Businessに紐付いている

異常時:

- 0件: 外部サービス側Logger/API送信ログを見る
- business未解決: `SourceAppConnection` / business_key確認
- evaluationなし: `/admin/activity_learning_e2e_check` の復旧ボタン

## 8. Google連携を見る

URL:

- `/admin/google_credentials`
- `/businesses/:id/google_settings`
- `/admin/google_api_imports`

見るもの:

- 全体Google Credentialの状態
- Business別GA4/GSC設定
- Refresh Token
- last_oauth_success_at
- 最終GA4/GSC取得
- Google API取得履歴

正常条件:

- 全体またはBusiness個別Credentialがconnected
- Business別Property/Site URLが明示される
- GA4/GSC再取得が開始できる
- 失敗時はGoogle API/OAuthエラー全文が出る

吸えログ:

- URL: `/businesses/2/google_settings`
- GA4 Property ID: `536889590`
- Business ID: `2`

## 9. AutoBuild / Resource Budgetを見る

URL:

- `/admin/aicoo_resource_budget`
- `/admin/auto_build_tasks`
- `/dashboard`

見るもの:

- Auto Build ON/OFF
- Build Queue
- Codex待機
- AI予算
- Learning Valueランキング

正常条件:

- Auto Build OFFならDaily Run stepはskippedでOK
- Auto Build ONの場合のみAutoBuildTaskが増える
- 新規LP/Lab Business以外の自動merge/deployはONにしない

## 10. 公開LPを見る

URL:

- `/`
- `/lp`
- `/lp/:published_slug`
- `/admin/aicoo_lab/public_landing_pages`
- `/sitemap.xml`

見るもの:

- 公開LPに内部文言が出ていない
- publishedのみ一覧/sitemapに出る
- pausedはnoindex・sitemap除外
- LPからAICOO内部リンクがない

正常条件:

- 公開側はBasic認証なし
- 管理側は認証あり
- sitemapがXMLで返る

## 11. 毎朝の判定表

| 順番 | URL | OK条件 | NGなら次 |
| --- | --- | --- | --- |
| 1 | `/owner/focus` | 改善候補と改訂待ちが見える | `/admin/pipeline_e2e_check` |
| 2 | `/admin/cron_health` | 今日Daily Run成功あり | `/aicoo_daily_runs` |
| 3 | `/aicoo_daily_runs/:id` | failedなし、warning理由明確 | Step詳細 |
| 4 | `/action_candidates` | 候補あり | `action_generation` metadata |
| 5 | `/auto_revision_tasks/codex_queue` | Task/Promptあり | AutoRevision設定 |
| 6 | `/admin/business_activity_logs` | Activityあり | Activity E2E |
| 7 | `/owner/learning_report` | 学習/推薦あり | ActionResult/ActivityEvaluation |

## 12. ONにしてよい設定

- AutoRevision Queue: ON
- Business auto_revision_mode: `approval` まで
- Resource Budget Auto Build: 新規LP/Lab検証で必要な場合のみON

## 13. まだ手動にしておく設定

- auto merge
- auto deploy
- high risk改修の自動実行
- 既存収益Businessの自動deploy
- Google Credential削除/再作成

## 14. 異常時の最短復旧ルート

### 改善候補がない

1. `/aicoo_daily_runs/:id`
2. `action_generation` step metadata
3. `/businesses/:id` でBusinessがDaily Run対象か確認
4. `/admin/pipeline_e2e_check`

### AutoRevisionTaskがない

1. `/admin/aicoo_auto_revision_settings`
2. AutoRevision QueueがONか確認
3. `/action_candidates` で `execution_prompt` あり候補を確認
4. `/admin/pipeline_e2e_check`

### Google取得できない

1. `/businesses/:id/google_settings`
2. `/admin/google_credentials`
3. `/admin/google_api_imports`
4. Daily Run `analytics_fetch` metadata

### Activity Logがない

1. `/admin/business_activity_logs`
2. `/admin/activity_learning_e2e_check`
3. `/admin/source_app_connections`
4. 外部サービスのActivity Loggerログ

### Cronが動いていない

1. `/admin/cron_health`
2. `/aicoo_daily_runs`
3. Render Cron Job command確認
4. `AICOO_DAILY_RUN_ENABLED=true` 確認

