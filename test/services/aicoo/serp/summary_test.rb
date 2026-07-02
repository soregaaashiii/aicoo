require "test_helper"

module Aicoo
  module Serp
    class SummaryTest < ActiveSupport::TestCase
      test "summarizes serp operation state" do
        business = businesses(:suelog)
        business.business_serp_keywords.create!(
          keyword: "梅田 喫煙",
          source: "manual",
          status: "active",
          priority_score: 90
        )
        business.serp_analyses.create!(
          keyword: "梅田 喫煙",
          analyzed_at: Time.current,
          search_engine: "google",
          device: "desktop",
          provider: "serper",
          status: "success",
          result_count: 10
        )

        summary = Summary.call

        assert_includes %w[Healthy Warning Broken], summary.health
        assert_operator summary.business_count, :>=, 1
        assert_operator summary.active_keyword_count, :>=, 1
        assert_operator summary.today_scan_count, :>=, 1
        assert_equal business, summary.top_priority_business
      end
    end
  end
end
