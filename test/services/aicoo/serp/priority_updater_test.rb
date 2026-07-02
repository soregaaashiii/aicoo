require "test_helper"

module Aicoo
  module Serp
    class PriorityUpdaterTest < ActiveSupport::TestCase
      test "updates priority and marks inactive candidates" do
        business = businesses(:suelog)
        keyword = business.business_serp_keywords.create!(
          keyword: "梅田 喫煙",
          source: "manual",
          status: "active",
          priority_score: 40,
          latest_clicks: 0,
          latest_impressions: 0,
          latest_rank: 12,
          check_count: 3,
          last_checked_at: 31.days.ago,
          metadata_json: { "previous_latest_rank" => 12 }
        )

        result = PriorityUpdater.update_all!

        assert_operator result.updated_count, :>=, 1
        keyword.reload
        assert_equal true, keyword.metadata_json["inactive_candidate"]
        assert_includes keyword.metadata_json["inactive_reasons"], "30日取得なし"
        assert_includes keyword.metadata_json["inactive_reasons"], "検索流入0"
        assert_includes keyword.metadata_json["inactive_reasons"], "順位変化なし"
      end

      test "keeps manual priority untouched" do
        business = businesses(:suelog)
        keyword = business.business_serp_keywords.create!(
          keyword: "手動 優先",
          source: "manual",
          status: "active",
          priority_score: 73,
          metadata_json: { "manual_priority" => true }
        )

        result = PriorityUpdater.update_all!

        assert_operator result.skipped_count, :>=, 1
        assert_equal 73, keyword.reload.priority_score
      end
    end
  end
end
