module OwnerModeLabelHelper
  OWNER_EVALUATOR_LABELS = {
    "gsc" => "検索流入",
    "ga4" => "サイト行動",
    "judge" => "予測精度",
    "revenue" => "売上記録",
    "learning" => "学習準備"
  }.freeze

  def owner_evaluator_label(evaluator_type)
    OWNER_EVALUATOR_LABELS.fetch(evaluator_type.to_s.downcase, evaluator_type.to_s)
  end
end
