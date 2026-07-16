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
    return if business.action_candidate_generation_blocked?

    title = "#{business.name}の予測精度に必要な学習データを増やす"
    return if recent_duplicate?(business, title)

    owner_messages = owner_messages_for(business_item)
    business.action_candidates.create!(
      title:,
      description: owner_messages.join("\n"),
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
      evaluation_reason: "予測精度を上げるための学習データが不足しています。\n#{owner_messages.join("\n")}",
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
      #{business.name}の予測精度に必要な学習データを増やしてください。

      不足:
      #{owner_messages_for(business_item).map { |message| "- #{message}" }.join("\n")}

      作業:
      - 実行済みの行動候補を最大#{action_result_shortage}件選び、実行結果を記録する
      - 日次指標が不足している場合は不足日数#{metric_shortage}日分を取り込む
      - 売上/費用が発生している場合は売上記録として入力する
      - 記録対象がない場合は、どのデータが未発生なのかをnoteに残す
      - 記録後に日次処理を実行して予測精度が改善できるか確認する
    PROMPT
  end

  def owner_messages_for(business_item)
    business = business_item.business
    business_item.missing_keys.map do |key|
      current = current_counts_for(business_item).fetch(key.to_s)
      required = required_counts_for(business_item).fetch(key.to_s)
      label =
        case key
        when :action_results
          "実行結果"
        when :evaluated
          "評価済み実行結果"
        when :revenue
          "売上記録"
        when :business_metric_daily
          "日次指標"
        else
          key.to_s
        end
      "#{business.name}: #{label} #{current}/#{required}件"
    end
  end

  def recent_duplicate?(business, title)
    business.action_candidates
            .where(created_at: 7.days.ago..)
            .where(title:)
            .exists?
  end
end
