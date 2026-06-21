module AicooRevenue
  class PlanBuilder
    Plan = Data.define(
      :selected_rows,
      :total_minutes,
      :total_budget_yen,
      :total_revenue_value_yen,
      :total_expected_90d_profit_yen,
      :total_neglect_loss_90d_yen,
      :available_minutes,
      :available_budget_yen
    )

    def initialize(available_minutes:, available_budget_yen:, rows: nil, source: "all")
      @available_minutes = available_minutes.presence&.to_i || RankingBuilder::DEFAULT_AVAILABLE_MINUTES
      @available_budget_yen = available_budget_yen.presence&.to_i || RankingBuilder::DEFAULT_AVAILABLE_BUDGET_YEN
      @rows = rows
      @source = source
    end

    def call
      selected_rows = select_rows

      Plan.new(
        selected_rows:,
        total_minutes: selected_rows.sum { |row| row.estimated_work_minutes.to_i },
        total_budget_yen: selected_rows.sum { |row| row.budget_yen.to_i },
        total_revenue_value_yen: selected_rows.sum { |row| row.revenue_total_value_yen.to_d },
        total_expected_90d_profit_yen: selected_rows.sum { |row| row.expected_90d_profit_yen.to_i },
        total_neglect_loss_90d_yen: selected_rows.sum { |row| row.neglect_loss_90d_yen.to_i },
        available_minutes:,
        available_budget_yen:
      )
    end

    private

    attr_reader :available_minutes, :available_budget_yen, :rows, :source

    def select_rows
      remaining_minutes = available_minutes
      remaining_budget_yen = available_budget_yen

      revenue_rows.each_with_object([]) do |row, selected|
        next if row.estimated_work_minutes.to_i > remaining_minutes
        next if row.budget_yen.to_i > remaining_budget_yen

        selected << row
        remaining_minutes -= row.estimated_work_minutes.to_i
        remaining_budget_yen -= row.budget_yen.to_i
      end
    end

    def revenue_rows
      source_rows = rows || RankingBuilder.new(
        available_minutes:,
        available_budget_yen:,
        source:
      ).call.revenue_rankings
      source_rows.sort_by { |row| -sortable_score(row.revenue_score) }
    end

    def sortable_score(value)
      value.infinite? ? Float::INFINITY : value.to_d
    end
  end
end
