# 自宅MacのcronでAICOO Daily Runを実行する

この手順は、自宅MacからAICOO Daily Runを安全に定期実行するための設定です。

同じ `bundle exec rails aicoo:daily_run` をRender Cronにも転用できます。無料版RenderではCronを使わず、これまで通りWeb画面から手動実行できます。

## 前提

- Macが起動していること
- Macがスリープしない設定になっていること
- ネット接続が維持されること
- Railsアプリのディレクトリに移動して実行すること
- `bundle exec rails aicoo:daily_run` がローカルで実行できること

## 仕組み

cronから実行するコマンドは以下です。

```sh
bundle exec rails aicoo:daily_run
```

このRake taskは既存の `AicooDailyRunScheduler` を呼び出します。

- 今日成功済みならScheduler側でskipします
- running中なら二重起動しません
- stuck判定、retry判定は既存Schedulerに委譲します
- `AICOO_DAILY_RUN_ENABLED=true` の時だけ起動します
- ENV未設定またはfalseなら `disabled` とログ出力して正常終了します

Web画面からの手動実行はこのENVに依存しません。

## Mac cron設定例

以下は毎日 7:00 / 12:00 / 18:00 / 23:00 JST に実行する例です。

```cron
0 7,12,18,23 * * * cd /Users/kawamuratakuya/Documents/Codex/2026-06-16/ruby-on-rails-ai-coo-ai-2 && AICOO_DAILY_RUN_ENABLED=true TZ=Asia/Tokyo bundle exec rails aicoo:daily_run >> log/aicoo_daily_run_cron.log 2>&1
```

## cron登録

現在のcronを退避しながら登録する例です。

```sh
crontab -l > /tmp/aicoo_crontab.backup
crontab -e
```

`crontab -e` が開いたら、上記のcron行を追加して保存します。

すでにcronが未登録の場合、`crontab -l` はエラーになることがあります。その場合はそのまま `crontab -e` で新規作成してください。

## cron確認

```sh
crontab -l
```

ログ確認:

```sh
cd /Users/kawamuratakuya/Documents/Codex/2026-06-16/ruby-on-rails-ai-coo-ai-2
tail -f log/aicoo_daily_run_cron.log
```

## cron削除

停止する場合は、編集してAICOO Daily Runの行だけ削除します。

```sh
crontab -e
```

全cronを削除する場合だけ、以下を使います。

```sh
crontab -r
```

`crontab -r` は他のcronもすべて消すため、通常は `crontab -e` で対象行だけ削除してください。

## 手動確認

ENV未設定時は起動しないことを確認:

```sh
bundle exec rails aicoo:daily_run
```

期待される出力:

```text
AICOO Daily Run cron disabled: AICOO_DAILY_RUN_ENABLED is not true.
```

cron有効時の確認:

```sh
AICOO_DAILY_RUN_ENABLED=true TZ=Asia/Tokyo bundle exec rails aicoo:daily_run
```

実行後は以下で確認します。

- `/admin/aicoo_daily_run_health`
- `/aicoo_daily_runs`
- `log/aicoo_daily_run_cron.log`

## Render Cronへの転用

Render有料化後は `docs/render_daily_run.md` の方式へ移行できます。Render有料Cronでは以下を設定します。

Command:

```sh
bundle exec rails aicoo:daily_run
```

ENV:

```sh
AICOO_DAILY_RUN_ENABLED=true
TZ=Asia/Tokyo
```

無料版RenderではCron Jobを設定しなくても、Web画面から手動実行できます。
