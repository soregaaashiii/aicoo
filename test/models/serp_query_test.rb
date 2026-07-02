require "test_helper"

class SerpQueryTest < ActiveSupport::TestCase
  test "normalizes query and enforces unique query per business" do
    business = businesses(:suelog)
    SerpQuery.create!(business:, query: " 大阪　喫煙 ", category: "existing_business")
    duplicate = SerpQuery.new(business:, query: "大阪 喫煙", category: "existing_business")

    assert_not duplicate.valid?
    assert_includes duplicate.errors[:normalized_query], "has already been taken"
  end

  test "tracks daily run limit" do
    business = businesses(:suelog)
    query = SerpQuery.create!(business:, query: "梅田 喫煙", category: "existing_business", daily_limit: 1)
    business.serp_analyses.create!(
      keyword: "梅田 喫煙",
      search_engine: "google",
      device: "desktop",
      status: "success",
      analyzed_at: Time.current
    )

    assert_not query.runnable_today?
    assert_equal "daily_limit_reached", query.next_run_reason
    assert_equal "未取得: 今日の上限により未実行", query.next_run_label
  end

  test "serp action candidate updates query candidate counters" do
    business = businesses(:suelog)
    query = SerpQuery.create!(business:, query: "警備 AI", category: "existing_business")

    ActionCandidate.create!(
      business:,
      title: "警備AIのSERP改善",
      status: "approved",
      action_type: "seo_improvement",
      generation_source: "serp",
      immediate_value_yen: 10_000,
      success_probability: 0.4,
      expected_hours: 1,
      metadata: { "source_query" => "警備 AI" }
    )

    query.reload
    assert_equal 1, query.total_candidates_generated
    assert_equal 1, query.total_candidates_approved
  end
end
