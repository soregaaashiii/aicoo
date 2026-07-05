require "test_helper"

class MetricActionCandidateGeneratorTest < ActiveSupport::TestCase
  setup do
    @business = businesses(:suelog)
    @today = Date.new(2026, 6, 21)
    DataSourceCostProfile.ensure_defaults!
    DataSourceCostProfile.find_by!(source_key: "serp").update!(api_key: nil)
  end

  test "seo media uses business analyzer instead of generic metric advice" do
    create_metric_series(default_impressions: 10, recent_impressions: 1_000, default_clicks: 0, recent_clicks: 5)

    result = MetricActionCandidateGenerator.new(business: @business, today: @today).call

    assert_not_empty result.created
    candidate = result.created.find { |record| record.metadata.fetch("issue_key") == "seo_low_ctr_titles" }
    assert candidate
    assert_equal "business_analyzer", candidate.generation_source
    assert_equal [ "gsc" ], candidate.metadata.dig("evidence", "source")
    assert_equal "seo_low_ctr_titles", candidate.metadata.dig("evidence", "issue_type")
    assert_equal "梅田 喫煙 居酒屋", candidate.metadata.dig("evidence", "query")
    assert_equal 0.005, candidate.metadata.dig("evidence", "current_value")
    assert_equal 0.03, candidate.metadata.dig("evidence", "benchmark_value")
    assert candidate.metadata.dig("evidence", "target_amount").present?
    assert_match(/CTR0\.5%/, candidate.title)
    assert_match(/件書き換える/, candidate.title)
    assert_match(/何を:/, candidate.evaluation_reason)
    assert_match(/どれだけ:/, candidate.evaluation_reason)
    assert_match(/なぜ:/, candidate.evaluation_reason)
    assert_match(/期待効果:/, candidate.evaluation_reason)
    assert_includes candidate.execution_prompt, "ActionCandidate実行指示書"
    assert_includes candidate.execution_prompt, "現在 → 変更後"
    assert_equal "Aicoo::BusinessAnalyzers::SeoBusinessAnalyzer", candidate.metadata.fetch("analyzer")
  end

  test "seo analyzer skips issues that cannot provide evidence" do
    analyzer = Aicoo::BusinessAnalyzers::SeoBusinessAnalyzer.new(business: @business, today: @today)
    issue = Aicoo::BusinessAnalyzers::BaseAnalyzer::Issue.new(
      key: "no_evidence",
      title: "抽象的な改善を行う",
      description: "根拠なし",
      action_type: "seo_improvement",
      quantity: nil,
      unit: nil,
      why: "根拠なし",
      expected_effect: "未算出",
      expected_value_yen: 1_000,
      success_probability: 0.1,
      strategic_value_score: 1,
      risk_reduction_score: 1,
      expected_hours: 1,
      confidence_score: 1,
      metadata: {}
    )

    refute analyzer.send(:evidence_present?, issue)
  end

  test "creates concrete conversion path task with amount and target pages" do
    create_metric_series(
      default_clicks: 5,
      recent_clicks: 10,
      default_pageviews: 100,
      recent_pageviews: 250,
      default_conversions: 0,
      recent_conversions: 0
    )

    result = MetricActionCandidateGenerator.new(business: @business, today: @today).call
    candidate = result.created.find { |record| record.metadata.fetch("issue_key") == "seo_conversion_path_zero" }

    assert candidate
    assert_match(/電話・地図・アフィリエイト導線を\d+ページに追加する/, candidate.title)
    assert_equal "ui_improvement", candidate.action_type
    assert_equal "phone_map_affiliate_clicks", candidate.metadata.fetch("source_metric")
    assert_includes candidate.metadata.fetch("candidate_pages"), "店舗詳細ページ"
    assert_includes candidate.metadata.fetch("completion_criteria").join("\n"), "phone_clicks"
  end

  test "creates concrete internal link task when navigation is weak" do
    create_metric_series(
      default_sessions: 20,
      recent_sessions: 20,
      default_pageviews: 60,
      recent_pageviews: 22,
      default_clicks: 1,
      recent_clicks: 3
    )

    result = MetricActionCandidateGenerator.new(business: @business, today: @today).call
    candidate = result.created.find { |record| record.metadata.fetch("issue_key") == "seo_internal_links_shortage" }

    assert candidate
    assert_match(/内部リンクを\d+件追加する/, candidate.title)
    assert_equal "seo_improvement", candidate.action_type
    assert_match(/Views\/Session/, candidate.evaluation_reason)
  end

  test "creates concrete shop data task for shop-like seo media" do
    create_metric_series(default_clicks: 0, recent_clicks: 0, default_impressions: 0, recent_impressions: 0)

    result = MetricActionCandidateGenerator.new(business: @business, today: @today).call
    candidate = result.created.find { |record| record.metadata.fetch("issue_key") == "seo_shop_data_shortage" }

    assert candidate
    assert_match(/エリアの掲載店舗を\d+件追加する/, candidate.title)
    assert_equal "data_preparation", candidate.action_type
    assert_equal "shop_activity", candidate.metadata.fetch("source_metric")
  end

  test "creates concrete content gap task from active serp queries" do
    @business.serp_queries.create!(query: "梅田 喫煙 居酒屋", priority: 10)
    @business.serp_queries.create!(query: "難波 喫煙 カフェ", priority: 20)
    @business.serp_queries.create!(query: "大阪 喫煙可能 飲食店", priority: 30)
    create_metric_series(default_impressions: 10, recent_impressions: 200, default_clicks: 0, recent_clicks: 3)

    result = MetricActionCandidateGenerator.new(business: @business, today: @today).call
    candidate = result.created.find { |record| record.metadata.fetch("issue_key") == "seo_content_gap_articles" }

    assert candidate
    assert_match(/記事を3本追加する/, candidate.title)
    assert_equal %w[梅田\ 喫煙\ 居酒屋 難波\ 喫煙\ カフェ 大阪\ 喫煙可能\ 飲食店], candidate.metadata.fetch("candidate_keywords")
  end

  test "creates serp-backed concrete rank opportunity" do
    keyword = "梅田 喫煙 カフェ"
    analysis = @business.serp_analyses.create!(
      keyword:,
      analyzed_at: @today - 1,
      search_engine: "google",
      device: "desktop",
      provider: "serper",
      status: "success",
      result_count: 10,
      competition_score: 82
    )
    analysis.serp_results.create!(position: 1, title: "梅田 喫煙 カフェ 比較", url: "https://example.com/1", snippet: "大阪 梅田で喫煙可のカフェを比較")
    analysis.serp_results.create!(position: 2, title: "大阪 喫煙可能 飲食店", url: "https://example.com/2", snippet: "紙タバコと加熱式に対応した飲食店")
    analysis.serp_results.create!(position: 3, title: "難波 喫煙可 居酒屋", url: "https://example.com/3", snippet: "難波で喫煙可能な居酒屋を探せます")

    result = MetricActionCandidateGenerator.new(business: @business, today: @today).call
    candidate = result.created.find { |record| record.metadata.fetch("issue_key") == "seo_rank_11_20_gap" }

    assert candidate
    assert_match(/梅田 喫煙 カフェ/, candidate.title)
    assert_equal analysis.id, candidate.metadata.fetch("serp_analysis_id")
    assert_equal keyword, candidate.metadata.fetch("source_query")
    assert_not_empty candidate.metadata.fetch("serp_top_results")
  end

  test "does not create duplicate analyzer candidate within seven days" do
    create_metric_series(default_impressions: 10, recent_impressions: 1_000, default_clicks: 0, recent_clicks: 5)
    @business.action_candidates.create!(
      title: "CTR0.5%の検索入口を5件書き換える",
      action_type: "seo_improvement",
      generation_source: "business_analyzer",
      evaluation_reason: "business_analyzer:seo_low_ctr_titles",
      created_at: @today.to_time
    )

    result = MetricActionCandidateGenerator.new(business: @business, today: @today).call

    assert result.skipped.any? { |reason| reason.include?("seo_low_ctr_titles: duplicate") }
    assert_equal 1, @business.action_candidates.where("evaluation_reason LIKE ?", "%business_analyzer:seo_low_ctr_titles%").count
  end

  test "saas business still falls back to existing generic generator" do
    business = businesses(:cards)
    30.times do |offset|
      date = @today - 29 + offset
      recent = date >= @today - 6
      business.business_metric_dailies.create!(
        recorded_on: date,
        impressions: recent ? 100 : 10,
        clicks: 5,
        sessions: 10,
        pageviews: 10
      )
    end

    result = MetricActionCandidateGenerator.new(business:, today: @today).call

    assert_not_empty result.created
    assert result.created.all? { |candidate| candidate.generation_source != "business_analyzer" }
  end

  private

  def create_metric_series(default_clicks: 0, recent_clicks: nil, default_impressions: 0, recent_impressions: nil,
                           default_sessions: 10, recent_sessions: nil, default_pageviews: 10, recent_pageviews: nil,
                           default_engagement_time: 120, recent_engagement_time: nil, default_bounce_rate: 0.3,
                           recent_bounce_rate: nil, default_conversions: 1, recent_conversions: nil)
    recent_clicks = default_clicks if recent_clicks.nil?
    recent_impressions = default_impressions if recent_impressions.nil?
    recent_sessions = default_sessions if recent_sessions.nil?
    recent_pageviews = default_pageviews if recent_pageviews.nil?
    recent_engagement_time = default_engagement_time if recent_engagement_time.nil?
    recent_bounce_rate = default_bounce_rate if recent_bounce_rate.nil?
    recent_conversions = default_conversions if recent_conversions.nil?

    30.times do |offset|
      date = @today - 29 + offset
      recent = date >= @today - 6
      @business.business_metric_dailies.create!(
        recorded_on: date,
        impressions: recent ? recent_impressions : default_impressions,
        clicks: recent ? recent_clicks : default_clicks,
        sessions: recent ? recent_sessions : default_sessions,
        pageviews: recent ? recent_pageviews : default_pageviews,
        average_engagement_time_seconds: recent ? recent_engagement_time : default_engagement_time,
        bounce_rate: recent ? recent_bounce_rate : default_bounce_rate,
        engagement_rate: recent ? 0.3 : 0.6,
        conversions: recent ? recent_conversions : default_conversions
      )
    end
  end
end
