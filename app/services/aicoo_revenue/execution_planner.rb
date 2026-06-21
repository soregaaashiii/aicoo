module AicooRevenue
  class ExecutionPlanner
    def initialize(source_type:, source_id:, available_minutes:, available_budget_yen:, source:)
      @source_type = source_type
      @source_id = source_id.to_i
      @available_minutes = available_minutes
      @available_budget_yen = available_budget_yen
      @source = source
    end

    def call
      row = ranking_row
      raise ActiveRecord::RecordNotFound, "Revenue row not found" unless row

      existing_execution = AicooRevenueExecution.planned.find_by(source_type: row.source, source_id: row.source_id)
      return existing_execution if existing_execution

      AicooRevenueExecution.create!(
        source_type: row.source,
        source_id: row.source_id,
        title: row.title,
        expected_90d_profit_yen: row.expected_90d_profit_yen,
        success_probability: row.success_probability,
        neglect_loss_90d_yen: row.neglect_loss_90d_yen,
        revenue_total_value_yen: row.revenue_total_value_yen,
        estimated_work_minutes: row.estimated_work_minutes,
        budget_yen: row.budget_yen,
        revenue_score: finite_score(row.revenue_score),
        status: "planned",
        planned_at: Time.current
      )
    end

    private

    attr_reader :source_type, :source_id, :available_minutes, :available_budget_yen, :source

    def ranking_row
      AicooRevenue::RankingBuilder.new(
        available_minutes:,
        available_budget_yen:,
        source:
      ).call.revenue_rankings.find do |row|
        row.source == source_type && row.source_id == source_id
      end
    end

    def finite_score(value)
      value == Float::INFINITY ? nil : value
    end
  end
end
