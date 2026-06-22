module AicooMetaEvaluator
  class Ga4Evaluator < BaseEvaluator
    def call
      sessions = recent_metrics.sum(:sessions)
      pageviews = recent_metrics.sum(:pageviews)
      depth = sessions.positive? ? pageviews.to_d / sessions : 0
      expected_value = (sessions * 30) + ([ 2 - depth, 0 ].max * sessions * 20).round
      confidence = [ capped_confidence(sessions, 1_000), capped_confidence(pageviews, 3_000) ].max

      result(
        evaluator_type: "ga4",
        expected_value_yen: expected_value,
        confidence_score: confidence,
        reason: reason_for(sessions, pageviews, depth),
        metadata: { sessions:, pageviews:, pageviews_per_session: depth.to_f }
      )
    end

    private

    def reason_for(sessions, _pageviews, depth)
      return "GA4相当のセッション・ページビューが不足しています。" if sessions.zero?
      return "流入はありますが回遊が弱く、内部リンクや導線改善余地があります。" if depth < 2

      "GA4指標は一定量あり、回遊も確認できます。"
    end
  end
end
