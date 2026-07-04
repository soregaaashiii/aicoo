# AICOO Codex Worker

AICOOが作成したGitHub Issueを、GitHub Actions上で自動的にPRへ変換するための運用メモです。

## 流れ

```text
AICOO Daily Run
↓
AutoRevisionTask
↓
CodexSubmission
↓
GitHub Issue作成
↓
GitHub Actions: AICOO Codex Worker
↓
OpenAIでunified diff生成
↓
作業ブランチ作成
↓
テスト実行
↓
PR作成
↓
AICOOでGitHub同期
↓
ActionResult / Learning
```

## 起動条件

`.github/workflows/aicoo-codex-worker.yml` は以下で起動します。

- `aicoo-codex` ラベル付きIssueが作成/編集/ラベル付けされたとき
- `aicoo` と `codex` の両方のラベルが付いたIssueが作成/編集/ラベル付けされたとき
- GitHub Actionsの `workflow_dispatch` でIssue番号を指定したとき

AICOOが作るIssueには `aicoo-codex` ラベルを付けます。

## 必須Secret

GitHub Repository Settings > Secrets and variables > Actions > Secrets に設定します。

| Secret | 用途 |
| --- | --- |
| `OPENAI_API_KEY` | Issue本文から実装diffを生成する |
| `AICOO_CODEX_CALLBACK_TOKEN` | PR作成後にAICOOへ結果を戻す |

`GITHUB_TOKEN` はGitHub Actionsが自動で提供するため、通常は追加設定不要です。

## 任意Secret / Variable

| 名前 | 種類 | 初期値 | 用途 |
| --- | --- | --- | --- |
| `OPENAI_MODEL` | Secret | `gpt-5.5` | 使用モデル |
| `AICOO_CODEX_MAX_RISK` | Variable | `low` | 自動PR化する最大risk |
| `AICOO_CODEX_BASE_BRANCH` | Variable | `main` | PRのbase branch |
| `AICOO_CODEX_DEFAULT_TEST_COMMANDS` | Variable | `bin/rails test` | OpenAIがテストを返さない場合の確認コマンド |
| `AICOO_CODEX_CALLBACK_URL` | Variable | なし | AICOO callback先。例: `https://aicoo.onrender.com` |

## AICOO側のENV

RenderのAICOO Web Serviceにも同じtokenを設定します。

```text
AICOO_CODEX_CALLBACK_TOKEN=...
```

GitHub Actions側の `AICOO_CODEX_CALLBACK_TOKEN` と完全一致させます。

## Callback

PR作成後、Workerは以下へPOSTします。

```text
POST /api/aicoo/codex_submissions/:id/github_tracking
Authorization: Bearer AICOO_CODEX_CALLBACK_TOKEN
```

これにより、AICOO側のCodexSubmissionに以下が自動保存されます。

- PR URL
- PR status
- CI status
- merge status
- deploy status
- changed files
- GitHub Actions run URL

## 安全ルール

- `risk:high` は初期設定では自動PR化しません。
- `risk:medium` も初期設定では自動PR化しません。必要なら `AICOO_CODEX_MAX_RISK=medium` にします。
- `db:drop` / `db:reset` / database削除 / `rm -rf` / `git reset` を含む確認コマンドは実行しません。
- Issueが曖昧でdiffを生成できない場合はPRを作らず、Issueに失敗理由をコメントします。

## 手動実行

GitHub Actionsから `AICOO Codex Worker` を選び、`Run workflow` でIssue番号を入力します。

## AICOO側で確認する場所

- `/admin/codex_submissions`
- `/admin/codex_connection`
- `/owner/auto_revision_loop`

GitHub ActionsがPRを作った後はcallbackで自動反映されます。callbackが未設定、または失敗した場合は、AICOOのCodexSubmission詳細で `GitHubから同期` を押すとPR URLと状態を取り込めます。
