module AicooInsight
  class Summary
    def total_count
      scope.count
    end

    def today_count
      scope.where(created_at: Time.current.all_day).count
    end

    def top_action
      scope.active_for_ranking.order(Arel.sql("expected_profit_yen DESC NULLS LAST, neglect_loss_90d_yen DESC NULLS LAST")).first
    end

    def recent_actions(limit = 20)
      scope.includes(:business).order(created_at: :desc).limit(limit)
    end

    private

    def scope
      ActionCandidate.where(generation_source: "ai_insight")
    end
  end
end
