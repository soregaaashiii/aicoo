# Render CronでAICOO Daily Runを自動実行する

このドキュメントは、Render有料化後にAICOO Daily RunをCron Jobから安全に起動するための設定メモです。

無料版ではCron Jobを設定しなくても、これまで通り画面から手動実行できます。アプリ本体や手動実行画面は `AICOO_DAILY_RUN_ENABLED` に依存しません。

## Cron Command

Render Cron JobのCommandには以下を設定します。

```sh
bundle exec rails aicoo:daily_run
```

このRake taskは既存の `AicooDailyRunScheduler` を呼び出します。今日すでに成功済みの場合、実行中の場合、retry上限に達している場合などの判定はScheduler側に寄せています。

SYSTEM MODEやOwner画面を開いただけでは、重いDaily Run本体は起動しません。画面では状態だけを確認し、実行は手動ボタンまたはRender Cron Jobから行います。

`render.yaml` には `aicoo-daily-run` Cron Jobを定義しています。Render Blueprintから反映すると、Web ServiceがスリープしていてもCron Job側のプロセスが独立して `bundle exec rails aicoo:daily_run` を起動します。

## ENV

RenderのCron JobまたはEnvironment Groupに以下を設定します。

```sh
AICOO_DAILY_RUN_ENABLED=true
TZ=Asia/Tokyo
```

`AICOO_DAILY_RUN_ENABLED` が `true` ではない場合、Cron用Rake taskはDaily Runを起動せず、disabledとして正常終了します。これは無料版や設定前のRenderで誤って重い処理が動かないようにするためです。

Cron JobにもWeb Serviceと同じDB接続を渡してください。

```sh
DATABASE_URL=...
SECRET_KEY_BASE=...
OPENAI_API_KEY=...
GOOGLE_CLIENT_ID=...
GOOGLE_CLIENT_SECRET=...
GOOGLE_REFRESH_TOKEN=...
AICOO_ACTIVITY_API_TOKEN=...
```

GoogleやSERPなど外部連携のENVが不足している場合でも、Daily Run全体を落とさず、該当stepだけskipped/warningとして記録する設計です。DBに保存すべき結果は `AicooDailyRun` / `AicooDailyRunStep` / 各アプリケーションテーブルへ保存し、Renderインスタンスのローカルファイルには依存しません。

## 推奨スケジュール

Daily Runは日本時間基準で運用します。

Render CronはUTC指定になるため、以下のようにJST相当へ変換して設定してください。

| JST | UTC |
| --- | --- |
| 07:00 | 22:00 前日 |
| 12:00 | 03:00 |
| 18:00 | 09:00 |
| 23:00 | 14:00 |

最初は1日1回から始め、安定後に回数を増やすのがおすすめです。

`render.yaml` の初期値は以下です。

```cron
0 22,3,9,14 * * *
```

これはJSTの 07:00 / 12:00 / 18:00 / 23:00 相当です。

## 無料版での使い方

無料版ではRender Cron Jobを作成しません。

- `/aicoo_daily_runs` から手動実行できます
- `/admin/aicoo_daily_run_health` でCron準備状態を確認できます
- `AICOO_DAILY_RUN_ENABLED` は未設定のままで問題ありません

## 有料化後にやること

1. Render Blueprintを再適用する、またはCron Jobを手動作成する
2. Cron Commandに `bundle exec rails aicoo:daily_run` を設定する
3. ENVに `AICOO_DAILY_RUN_ENABLED=true` を設定する
4. ENVに `TZ=Asia/Tokyo` を設定する
5. Cron JobにWeb Serviceと同じ `DATABASE_URL` と必要なAPI ENVを設定する
6. `/admin/aicoo_daily_run_health` で `Daily Run Mode: Cron Ready` を確認する
7. Cron実行後に `/aicoo_daily_runs` で履歴を確認する

## ローカル確認

Cron有効時の動作確認:

```sh
AICOO_DAILY_RUN_ENABLED=true bundle exec rails aicoo:daily_run
```

Cron無効時の安全確認:

```sh
bundle exec rails aicoo:daily_run
```

無効時はDaily Runを起動せず、disabledとして正常終了します。
