module BusinessesHelper
  AUTO_REVISION_MODE_LABELS = {
    "manual" => "Manual",
    "approval" => "Approval",
    "automatic" => "Automatic"
  }.freeze

  AUTO_REVISION_MODE_DESCRIPTIONS = {
    "manual" => "提案のみ。人が必要な時だけ進めます。",
    "approval" => "提案を承認してからCodexへ進めます。",
    "automatic" => "低リスクだけ自動でCodex投入準備まで進めます。Deployは承認制です。"
  }.freeze

  AUTO_DEPLOY_MODE_LABELS = {
    "manual" => "Manual",
    "approval" => "Approval",
    "automatic" => "Automatic"
  }.freeze

  AUTO_DEPLOY_MODE_DESCRIPTIONS = {
    "manual" => "Deploy提案だけ作成します。実行はしません。",
    "approval" => "Codex改訂後、Deploy承認待ちにします。",
    "automatic" => "自動改訂Automaticかつ低リスク・テスト成功・Precheck通過時だけ自動Deploy候補に進めます。"
  }.freeze

  LIFECYCLE_STAGE_LABELS = {
    "idea" => "Idea",
    "lp_validation" => "LP検証",
    "mvp" => "MVP",
    "production" => "サービス公開",
    "scaling" => "拡大",
    "pivot" => "Pivot",
    "archived" => "Archived"
  }.freeze

  LIFECYCLE_STAGE_DESCRIPTIONS = {
    "idea" => "アイデアと仮説を整理する段階です。",
    "lp_validation" => "LPで需要と反応を検証する段階です。",
    "mvp" => "最小サービスを作り、実利用を確認する段階です。",
    "production" => "本番サービスとして運用・改善する段階です。",
    "scaling" => "伸びている事業を拡大する段階です。",
    "pivot" => "方向転換して次の仮説を検証する段階です。",
    "archived" => "停止または終了した事業です。"
  }.freeze

  RESOURCE_STATUS_LABELS = {
    "active" => "Active",
    "watch" => "Watch",
    "paused" => "Paused",
    "archived" => "Archived"
  }.freeze

  RESOURCE_STATUS_DESCRIPTIONS = {
    "active" => "通常運用・改善対象です。",
    "watch" => "自動計測のみ継続し、Owner対応は基本不要です。",
    "paused" => "改善・自動改修を止め、最低限の監視だけ継続します。",
    "archived" => "履歴保存のみで、日次運用から外します。"
  }.freeze

  def auto_revision_mode_label(mode)
    AUTO_REVISION_MODE_LABELS.fetch(mode.to_s, mode.to_s)
  end

  def auto_revision_mode_description(mode)
    AUTO_REVISION_MODE_DESCRIPTIONS.fetch(mode.to_s, "-")
  end

  def auto_deploy_mode_label(mode)
    AUTO_DEPLOY_MODE_LABELS.fetch(mode.to_s, mode.to_s)
  end

  def auto_deploy_mode_description(mode)
    AUTO_DEPLOY_MODE_DESCRIPTIONS.fetch(mode.to_s, "-")
  end

  def lifecycle_stage_label(stage)
    LIFECYCLE_STAGE_LABELS.fetch(stage.to_s, stage.to_s)
  end

  def lifecycle_stage_description(stage)
    LIFECYCLE_STAGE_DESCRIPTIONS.fetch(stage.to_s, "-")
  end

  def resource_status_label(status)
    RESOURCE_STATUS_LABELS.fetch(status.to_s, status.to_s)
  end

  def resource_status_description(status)
    RESOURCE_STATUS_DESCRIPTIONS.fetch(status.to_s, "-")
  end

  def business_service_status_label(status)
    {
      "planning" => "計画中",
      "building" => "構築中",
      "live" => "公開中",
      "production" => "本番運用",
      "paused" => "停止中",
      "archived" => "終了"
    }.fetch(status.to_s, status.to_s)
  end
end
