class CorrectionReadinessActionCandidateGenerator
  Result = Data.define(:created, :skipped)

  def self.generate_all!
    new.call
  end

  def call
    readiness = AicooCorrectionReadinessService.new.call
    created = readiness.business_items.filter_map { |business_item| create_candidate_for(business_item) }
    Result.new(created:, skipped: readiness.business_items.count(&:ready?))
  end

  private

  def create_candidate_for(business_item)
    return if business_item.ready?

    business = business_item.business
    title = "#{business.name}のJudge補正に必要な不足データを増やす"
    return if recent_duplicate?(business, title)

    business.action_candidates.create!(
      title:,
      description: business_item.messages.join("\n"),
      action_type: "data_preparation",
      immediate_value_yen: 0,
      success_probability: 0.6,
      strategic_value_score: 45,
      risk_reduction_score: 70,
      confidence_score: 60,
      data_confidence_score: 30,
      expected_hours: 1,
      cost_yen: 0,
      generation_source: "ai_business",
      metadata: metadata_for(business_item),
      evaluation_reason: "Judge補正に必要なデータが不足しています。\n#{business_item.messages.join("\n")}",
      execution_prompt: execution_prompt_for(business_item)
    )
  end

  def metadata_for(business_item)
    {
      "metric_rule" => "correction_readiness",
      "missing_type" => business_item.missing_keys.map(&:to_s),
      "required_count" => required_counts_for(business_item),
      "current_count" => current_counts_for(business_item),
      "business_id" => business_item.business.id
    }
  end

  def required_counts_for(_business_item)
    {
      "action_results" => AicooCorrectionReadinessService::ACTION_RESULT_REQUIRED,
      "evaluated" => AicooCorrectionReadinessService::EVALUATED_REQUIRED,
      "revenue" => 1,
      "business_metric_daily" => AicooCorrectionReadinessService::BUSINESS_METRIC_DAILY_REQUIRED
    }
  end

  def current_counts_for(business_item)
    business = business_item.business
    {
      "action_results" => business.action_results.count,
      "evaluated" => business.action_results.evaluated.count,
      "revenue" => business.revenue_events.revenue.count,
      "business_metric_daily" => business.business_metric_dailies.count
    }
  end

  def execution_prompt_for(business_item)
    business = business_item.business
    action_result_shortage = [ AicooCorrectionReadinessService::ACTION_RESULT_REQUIRED - business.action_results.count, 0 ].max
    metric_shortage = [ AicooCorrectionReadinessService::BUSINESS_METRIC_DAILY_REQUIRED - business.business_metric_dailies.count, 0 ].max

    <<~PROMPT
      #{business.name}のJudge補正に必要な不足データを増やしてください。

      不足:
      #{business_item.messages.map { |message| "- #{message}" }.join("\n")}

      作業:
      - 実行済みActionCandidateを最大#{action_result_shortage}件選び、実行結果をActionResultに記録する
      - BusinessMetricDailyが不足している場合は不足日数#{metric_shortage}日分を取り込む
      - 売上/費用が発生している場合はRevenueEventを記録する
      - 記録対象がない場合は、どのデータが未発生なのかをnoteに残す
      - 記録後にDaily Runを実行してJudge補正が効くか確認する
    PROMPT
  end

  def recent_duplicate?(business, title)
    business.action_candidates
            .where(created_at: 7.days.ago..)
            .where(title:)
            .exists?
  end
end
