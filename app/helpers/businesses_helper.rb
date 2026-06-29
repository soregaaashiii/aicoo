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
end
