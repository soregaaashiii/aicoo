class LearningValueCalculator
  ACTION_TYPE_VALUES = {
    "data_preparation" => 8_000,
    "market_research" => 6_000,
    "serp_research" => 5_000,
    "build_lp" => 7_000,
    "build_mvp" => 7_000,
    "pivot" => 4_000,
    "withdraw" => 3_000
  }.freeze

  KEYWORD_VALUES = {
    /ActionResult|実行結果|Judge|予測精度|補正/i => 8_000,
    /BusinessMetricDaily|proxy_score|代理指標/i => 7_000,
    /LP|ランディング|事前登録|検証/i => 6_000,
    /市場|SERP|競合|調査/i => 5_000,
    /新規事業|仮説|学習/i => 5_000
  }.freeze

  def initialize(action_candidate)
    @action_candidate = action_candidate
  end

  def value_yen
    [
      action_type_value,
      keyword_value,
      metadata_value,
      data_confidence_gap_value,
      strategic_learning_value
    ].sum.round
  end

  private

  attr_reader :action_candidate

  def action_type_value
    ACTION_TYPE_VALUES.fetch(action_candidate.action_type, 0)
  end

  def keyword_value
    text = [
      action_candidate.title,
      action_candidate.description,
      action_candidate.evaluation_reason,
      action_candidate.execution_prompt
    ].compact.join("\n")

    KEYWORD_VALUES.sum { |pattern, value| text.match?(pattern) ? value : 0 }
  end

  def metadata_value
    metadata = action_candidate.metadata.to_h
    value = 0
    value += 6_000 if metadata["metric_rule"].present?
    value += 5_000 if metadata["missing_type"].present?
    value
  end

  def data_confidence_gap_value
    confidence_gap = 100 - action_candidate.data_confidence_score.to_i
    return 0 if confidence_gap <= 0

    [ confidence_gap * 50, 4_000 ].min
  end

  def strategic_learning_value
    action_candidate.strategic_value_score.to_i * 30
  end
end
