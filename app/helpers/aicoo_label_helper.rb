module AicooLabelHelper
  LAB_STATUS_LABELS = {
    "candidate" => "事業アイデア",
    "proposed" => "提案中",
    "preview_ready" => "LP作成済み",
    "approval_pending" => "承認待ち",
    "approved" => "承認済み",
    "running" => "検証中",
    "rejected" => "却下",
    "converted" => "LP化済み",
    "done" => "完了",
    "failed" => "失敗",
    "success" => "成功",
    "paused" => "一時停止",
    "draft" => "下書き",
    "published" => "公開中",
    "unpublished" => "非公開"
  }.freeze

  EXECUTOR_STATUS_LABELS = {
    "draft" => "下書き",
    "approval_pending" => "実行承認待ち",
    "approved" => "実行承認済み",
    "done" => "完了",
    "rejected" => "却下"
  }.freeze

  SOURCE_LABELS = {
    "candidate" => "事業アイデア",
    "experiment" => "検証",
    "action_candidate" => "行動候補",
    "human" => "人間",
    "lab" => "新規事業",
    "revenue" => "今日やること",
    "lab_experiment" => "新規事業検証",
    "revenue_execution" => "収益実行記録",
    "landing_page" => "LP実績データ",
    "ga4" => "GA4実績データ",
    "gsc" => "GSC実績データ"
  }.freeze

  def aicoo_label(value)
    SOURCE_LABELS.fetch(value.to_s, LAB_STATUS_LABELS.fetch(value.to_s, EXECUTOR_STATUS_LABELS.fetch(value.to_s, value.to_s)))
  end

  def aicoo_lab_status_label(status)
    LAB_STATUS_LABELS.fetch(status.to_s, status.to_s)
  end

  def aicoo_executor_status_label(status)
    EXECUTOR_STATUS_LABELS.fetch(status.to_s, status.to_s)
  end

  def aicoo_source_label(source)
    SOURCE_LABELS.fetch(source.to_s, source.to_s)
  end
end
