require "test_helper"

module Aicoo
  module Serp
    class RunPlannerTest < ActiveSupport::TestCase
      test "plans only the market exploration run and no business scoped query ids" do
        business = businesses(:suelog)
        business.serp_queries.create!(
          query: "吸えログ 比較 #{SecureRandom.hex(4)}",
          category: "existing_business",
          priority: 1,
          daily_limit: 5
        )

        planner = Aicoo::Serp::RunPlanner.new(max_total_queries: 10)

        assert_equal [], planner.run_query_ids
        assert_equal 1, planner.metadata.dig("plan", "rows").size
        assert_equal "AICOO Market Exploration", planner.metadata.dig("plan", "rows").first["business_name"]
        assert_equal "new_business_exploration", planner.metadata.dig("plan", "rows").first["reason"]
      end
    end
  end
end
