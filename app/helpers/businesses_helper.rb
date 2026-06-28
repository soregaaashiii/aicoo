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

  def auto_revision_mode_label(mode)
    AUTO_REVISION_MODE_LABELS.fetch(mode.to_s, mode.to_s)
  end

  def auto_revision_mode_description(mode)
    AUTO_REVISION_MODE_DESCRIPTIONS.fetch(mode.to_s, "-")
  end
end
