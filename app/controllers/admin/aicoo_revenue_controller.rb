module Admin
  class AicooRevenueController < ApplicationController
    def show
      @available_minutes = params.fetch(:available_minutes, ::AicooRevenue::RankingBuilder::DEFAULT_AVAILABLE_MINUTES)
      @available_budget_yen = params.fetch(:available_budget_yen, ::AicooRevenue::RankingBuilder::DEFAULT_AVAILABLE_BUDGET_YEN)
      @result = ::AicooRevenue::RankingBuilder.new(
        available_minutes: @available_minutes,
        available_budget_yen: @available_budget_yen,
        source: params.fetch(:source, "all")
      ).call
      @top_revenue_action = @result.revenue_rankings.first
      @today_revenue_candidates = @result.revenue_rankings.first(5)
      @neglect_alerts = @result.neglect_alerts
      @planned_execution_keys = planned_execution_keys
      @revenue_plan = ::AicooRevenue::PlanBuilder.new(
        available_minutes: @result.available_minutes,
        available_budget_yen: @result.available_budget_yen,
        rows: @result.revenue_rankings
      ).call
    end

    private

    def planned_execution_keys
      ::AicooRevenueExecution.planned.pluck(:source_type, :source_id).map { |source_type, source_id| "#{source_type}:#{source_id}" }
    end
  end
end
