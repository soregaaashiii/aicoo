module AicooMetaEvaluator
  class GscEvaluator < BaseEvaluator
    def call
      impressions = recent_metrics.sum(:impressions)
      clicks = recent_metrics.sum(:clicks)
      ctr = impressions.positive? ? clicks.to_d / impressions : 0
      opportunity_clicks = [ (impressions * 0.03).round - clicks, 0 ].max
      expected_value = opportunity_clicks * 100
      confidence = capped_confidence(impressions, 5_000)
      confidence = [ confidence, capped_confidence(clicks, 200) ].max if clicks.positive?

      result(
        evaluator_type: "gsc",
        expected_value_yen: expected_value,
        confidence_score: confidence,
        reason: reason_for(impressions, clicks, ctr, opportunity_clicks),
        metadata: { impressions:, clicks:, ctr: ctr.to_f, opportunity_clicks: }
      )
    end

    private

    def reason_for(impressions, clicks, ctr, opportunity_clicks)
      return "GSC相当の表示・クリックデータが不足しています。" if impressions.zero?
      return "表示回数はありますがクリックが少なく、CTR改善余地があります。" if opportunity_clicks.positive?

      "GSC指標は安定しています。CTR #{(ctr * 100).round(2)}% を確認しました。"
    end
  end
end
