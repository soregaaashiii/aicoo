require "test_helper"

module Aicoo
  module Serp
    class RunPlannerTest < ActiveSupport::TestCase
      test "plans only selected business queries and records skipped reasons" do
        business = businesses(:suelog)
        other_business = businesses(:cards)
        runnable = business.serp_queries.create!(
          query: "梅田 喫煙 カフェ #{SecureRandom.hex(4)}",
          category: "existing_business",
          priority: 1,
          daily_limit: 5
        )
        paused = business.serp_queries.create!(
          query: "難波 喫煙 バー #{SecureRandom.hex(4)}",
          category: "existing_business",
          status: "paused",
          enabled: false,
          priority: 2
        )
        other_business.serp_queries.create!(
          query: "名刺 共有 #{SecureRandom.hex(4)}",
          category: "existing_business",
          priority: 1,
          daily_limit: 5
        )

        planner = Aicoo::Serp::RunPlanner.new(target_businesses: [ business ], max_total_queries: 10)

        assert_equal [ runnable.id ], planner.run_query_ids
        assert_equal 2, planner.rows.size
        assert_equal "paused", planner.rows.find { |row| row.serp_query == paused }.reason
        assert planner.metadata.dig("plan", "rows").all? { |row| row["business_id"] == business.id }
      end

      test "honors global daily limit" do
        business = businesses(:suelog)
        first = business.serp_queries.create!(query: "大阪 喫煙 #{SecureRandom.hex(4)}", category: "existing_business", priority: 1, daily_limit: 5)
        second = business.serp_queries.create!(query: "京都 喫煙 #{SecureRandom.hex(4)}", category: "existing_business", priority: 2, daily_limit: 5)

        planner = Aicoo::Serp::RunPlanner.new(target_businesses: [ business ], max_total_queries: 1)

        assert_equal [ first.id ], planner.run_query_ids
        assert_equal "global_daily_limit", planner.rows.find { |row| row.serp_query == second }.reason
      end
    end
  end
end
