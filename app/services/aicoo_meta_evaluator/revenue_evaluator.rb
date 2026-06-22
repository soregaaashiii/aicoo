module AicooMetaEvaluator
  class RevenueEvaluator < BaseEvaluator
    def call
      revenue_count = business.revenue_events.revenue.count
      profit_90d = profit_for(90.days.ago.to_date..Date.current)
      confidence = capped_confidence(revenue_count, 50)
      expected_value = [ profit_90d / 3, 0 ].max

      result(
        evaluator_type: "revenue",
        expected_value_yen: expected_value,
        confidence_score: confidence,
        reason: reason_for(revenue_count, profit_90d),
        metadata: { revenue_event_count: revenue_count, profit_90d_yen: profit_90d }
      )
    end

    private

    def profit_for(range)
      business.revenue_events.revenue.where(occurred_on: range).sum(:amount) -
        business.revenue_events.expense.where(occurred_on: range).sum(:amount)
    end

    def reason_for(revenue_count, profit_90d)
      return "RevenueEventがないため、実収益ベースの評価はまだ使えません。" if revenue_count.zero?

      "RevenueEventが#{revenue_count}件あり、直近90日利益#{profit_90d}円を確認しました。"
    end
  end
end
