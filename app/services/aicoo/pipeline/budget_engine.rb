module Aicoo
  module Pipeline
    class BudgetEngine
      DEFAULT_MONTHLY_BUDGET_YEN = 1_000

      def initialize(subject, estimated_cost_yen:)
        @subject = subject
        @estimated_cost_yen = estimated_cost_yen.to_d
      end

      def call
        {
          "monthly_budget_yen" => monthly_budget_yen.to_s,
          "month_to_date_cost_yen" => month_to_date_cost_yen.to_s,
          "estimated_cost_yen" => estimated_cost_yen.to_s,
          "projected_cost_yen" => (month_to_date_cost_yen + estimated_cost_yen).to_s,
          "over_budget" => (month_to_date_cost_yen + estimated_cost_yen) > monthly_budget_yen
        }
      end

      private

      attr_reader :subject, :estimated_cost_yen

      def monthly_budget_yen
        DataSourceCostProfile.find_by(source_key: "serp")&.monthly_budget_yen.to_d.presence ||
          DEFAULT_MONTHLY_BUDGET_YEN.to_d
      end

      def month_to_date_cost_yen
        DataSourceCostProfile.find_by(source_key: "serp")&.monthly_spend_yen.to_d || 0.to_d
      end
    end
  end
end
