require "test_helper"
require "csv"

class MetricActionCandidateGeneratorTest < ActiveSupport::TestCase
  setup do
    @business = businesses(:suelog)
    @today = Date.new(2026, 6, 21)
    DataSourceCostProfile.ensure_defaults!
    DataSourceCostProfile.find_by!(source_key: "serp").update!(api_key: nil)
  end

  test "generic opportunity analyzer creates concrete low ctr opportunity" do
    create_metric_series(default_impressions: 10, recent_impressions: 1_000, default_clicks: 0, recent_clicks: 5)

    result = MetricActionCandidateGenerator.new(business: @business, today: @today).call

    assert_not_empty result.created
    candidate = result.created.find { |record| record.metadata.fetch("issue_key") == "high_impression_low_ctr" }
    assert candidate
    assert_equal "business_analyzer", candidate.generation_source
    assert_includes candidate.metadata.dig("evidence", "source"), "gsc"
    assert_equal "high_impression_low_ctr", candidate.metadata.dig("evidence", "issue_type")
    assert_equal "吸えログ 比較", candidate.metadata.dig("evidence", "query")
    assert_in_delta 0.005, candidate.metadata.dig("evidence", "current_value").to_d, 0.001
    assert_equal 0.03, candidate.metadata.dig("evidence", "benchmark_value")
    assert_equal "high_impression_low_ctr", candidate.metadata.fetch("opportunity_type")
    assert candidate.metadata.fetch("concrete_task").present?
    assert_equal candidate.title, candidate.metadata.dig("action_plan", "summary")
    assert_includes candidate.metadata.dig("action_plan", "owner_output"), "今日やること:"
    assert_includes candidate.metadata.dig("action_plan", "owner_output"), candidate.title
    assert_not_empty candidate.metadata.dig("action_plan", "execution_steps")
    assert_not_empty candidate.metadata.dig("action_plan", "execution_units")
    assert candidate.metadata.dig("evidence", "target_amount").present?
    assert_match(/タイトル|meta description|FAQ|内部リンク/, candidate.title)
    assert_equal "high_impression_low_ctr", candidate.metadata.dig("opportunity", "key")
    assert_equal "high_impression_low_ctr", candidate.metadata.dig("opportunity", "opportunity_type")
    assert_equal "「吸えログ 比較」", candidate.metadata.dig("opportunity", "target", "label")
    assert_equal "content_creation", candidate.metadata.dig("opportunity", "execution_mode")
    assert_includes candidate.metadata.dig("opportunity", "supporting_metrics", "source"), "gsc"
    assert_equal candidate.title, candidate.metadata.dig("decision", "selected", "concrete_task")
    assert candidate.metadata.dig("decision", "selected", "asset_type").present?
    assert_equal "Aicoo::UniversalImprovementStrategyEngine", candidate.metadata.fetch("strategy_engine")
    assert candidate.metadata.dig("strategy_ranking", "adopted").present?
    assert_not_empty candidate.metadata.dig("strategy_ranking", "rejected")
    assert candidate.metadata.dig("business_knowledge", "assets").present?
    assert_equal false, candidate.metadata.fetch("codex_eligible")
    assert_match(/今日やること:/, candidate.evaluation_reason)
    assert_match(/理由:/, candidate.evaluation_reason)
    assert_match(/期待効果:/, candidate.evaluation_reason)
    assert_nil candidate.execution_prompt
    generated_memo = Aicoo::ExecutionPromptBuilder.new(candidate).call
    assert_includes generated_memo, "AICOO Action 作業メモ"
    assert_includes generated_memo, "## 実行手順"
    assert_no_match(/Codex実装指示|変更ファイル|本文案|現在 → 変更後|Codexへ渡す修正文|After（AI生成）/, generated_memo)
    assert_equal "Aicoo::BusinessAnalyzers::GenericOpportunityAnalyzer", candidate.metadata.fetch("analyzer")
  end

  test "suelog site insights adapter creates many concrete ranked todos" do
    @business.update!(project_key: "suelog", repository_name: "suelog")
    queries = [
      "梅田 喫煙 居酒屋",
      "梅田 喫煙 カフェ",
      "難波 喫煙 居酒屋",
      "東通り 居酒屋 喫煙可",
      "曽根崎 バー 喫煙可能",
      "北新地 個室 喫煙",
      "堂山 深夜 喫煙 居酒屋",
      "心斎橋 喫煙 バー",
      "西中島 喫煙 焼肉",
      "本町 喫煙 カフェ",
      "天満 焼鳥 喫煙可",
      "福島 喫煙 デート"
    ]
    create_gsc_import(queries)
    @business.serp_queries.create!(query: "SERPだけの参考キーワード", priority: 1)
    BusinessActivityLog.record!(
      business: @business,
      attributes: {
        source_app: "suelog",
        activity_type: "shop_created",
        title: "梅田 居酒屋 喫煙可 店舗登録",
        resource_type: "Shop",
        resource_id: "shop-1",
        occurred_at: @today.to_time
      }
    )
    BusinessActivityLog.record!(
      business: @business,
      attributes: {
        source_app: "suelog",
        activity_type: "article_created",
        title: "梅田で喫煙できる居酒屋まとめ",
        resource_type: "Article",
        resource_id: "umeda-smoking-izakaya",
        metadata: { slug: "umeda-smoking-izakaya" },
        occurred_at: @today.to_time
      }
    )
    create_metric_series(
      default_impressions: 200,
      recent_impressions: 1_200,
      default_clicks: 4,
      recent_clicks: 12,
      default_pageviews: 80,
      recent_pageviews: 220,
      default_conversions: 0,
      recent_conversions: 0
    )
    @business.business_metric_dailies.update_all(average_position: 12)

    result = MetricActionCandidateGenerator.new(business: @business, today: @today).call

    assert_operator result.created.size, :>=, 10
    assert result.created.all? { |candidate| candidate.metadata["suelog_site_insights"] }
    assert result.created.all? { |candidate| candidate.metadata["query"].present? }
    assert result.created.none? { |candidate| candidate.metadata["query"] == "SERPだけの参考キーワード" }
    assert result.created.none? { |candidate| Array(candidate.metadata.dig("evidence", "source")).include?("serp") }
    assert result.created.all? { |candidate| candidate.metadata["expected_score"].present? }
    assert result.created.all? { |candidate| candidate.metadata["roi_score"].present? }
    assert result.created.all? { |candidate| candidate.metadata["work_cost"].present? }
    assert result.created.all? { |candidate| candidate.metadata["recommended_action"].present? }
    assert result.created.all? { |candidate| candidate.metadata["action_plan"].to_h["execution_steps"].present? }
    assert result.created.all? { |candidate| candidate.metadata["concrete_task"].present? }
    assert result.created.none? { |candidate| candidate.title.match?(/検索需要があるテーマ|SEO改善|CV改善|導線改善|要具体化/) }
  end

  test "suelog site insights adapter does not generate from serp alone" do
    @business.update!(project_key: "suelog", repository_name: "suelog")
    @business.serp_queries.create!(query: "梅田 喫煙 居酒屋", priority: 1)

    result = MetricActionCandidateGenerator.new(business: @business, today: @today).call

    assert result.created.none? { |candidate| candidate.metadata["suelog_site_insights"] }
    assert result.created.none? { |candidate| candidate.generation_source == "serp" }
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

  test "seo analyzer requires seo action type for seo media candidates" do
    analyzer = Aicoo::BusinessAnalyzers::SeoBusinessAnalyzer.new(business: @business, today: @today)
    issue = Aicoo::BusinessAnalyzers::BaseAnalyzer::Issue.new(
      key: "missing_seo_action_type",
      title: "梅田の記事を3本追加する",
      description: "根拠はあるが作業カテゴリなし",
      action_type: "seo_article",
      quantity: 3,
      unit: "本",
      why: "検索需要があるため",
      expected_effect: "+60クリック/月",
      expected_value_yen: 10_000,
      success_probability: 0.3,
      strategic_value_score: 40,
      risk_reduction_score: 20,
      expected_hours: 2,
      confidence_score: 40,
      metadata: { "source_query" => "梅田 喫煙 居酒屋" }
    )

    refute analyzer.send(:seo_action_type_present?, issue)
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
    candidate = result.created.find { |record| record.metadata.fetch("issue_key") == "high_traffic_low_conversion" }

    assert candidate
    assert_match(/流入上位\d+ページ/, candidate.title)
    assert_equal "ui_improvement", candidate.action_type
    assert_equal "high_traffic_low_conversion", candidate.metadata.fetch("opportunity_type")
    assert_includes %w[code_revision content_creation], candidate.metadata.fetch("execution_mode")
    assert_equal candidate.metadata.fetch("execution_mode") == "code_revision", candidate.metadata.fetch("codex_eligible")
    assert_equal "high_traffic_low_conversion", candidate.metadata.fetch("source_metric")
    assert candidate.metadata.fetch("execution_units").any?
    assert_match(/導線|内部リンク/, candidate.metadata.fetch("execution_units").first.fetch("label"))
    assert_includes candidate.metadata.fetch("candidate_pages"), "流入上位ページ"
    assert_operator candidate.metadata.dig("strategy_ranking", "rejected").size, :>, 0
  end

  test "creates asset without traffic opportunity from recent asset activity" do
    BusinessActivityLog.record!(
      business: @business,
      attributes: {
        source_app: "test",
        activity_type: "article_created",
        title: "料金比較記事を公開",
        resource_type: "Article",
        resource_id: "article-1",
        occurred_at: @today.to_time
      }
    )
    create_metric_series(
      default_sessions: 0,
      recent_sessions: 0,
      default_pageviews: 0,
      recent_pageviews: 0,
      default_clicks: 0,
      recent_clicks: 0
    )

    result = MetricActionCandidateGenerator.new(business: @business, today: @today).call
    candidate = result.created.find { |record| record.metadata.fetch("issue_key") == "asset_without_traffic" }

    assert candidate
    assert_match(/導線を3件追加する/, candidate.title)
    assert_equal "seo_improvement", candidate.action_type
    assert_equal "asset_without_traffic", candidate.metadata.fetch("opportunity_type")
    assert_equal "content_creation", candidate.metadata.fetch("execution_mode")
    assert_match(/Activity/, candidate.evaluation_reason)
  end

  test "business capability profile is generic and not tied to business name" do
    business = businesses(:cards)
    business.update!(
      metadata: {
        "capabilities" => {
          "has_articles" => true,
          "has_lp" => true,
          "conversion_events" => [ "signup" ],
          "primary_assets" => [ "lp", "article" ]
        }
      }
    )

    profile = Aicoo::BusinessCapabilityProfile.for(business)

    assert profile.has_articles
    assert profile.has_lp
    assert_equal [ "signup" ], profile.conversion_events
    assert_includes profile.primary_assets, "lp"
  end

  test "creates generic activity gap task without shop-specific branching" do
    create_metric_series(default_clicks: 0, recent_clicks: 0, default_impressions: 0, recent_impressions: 0)

    result = MetricActionCandidateGenerator.new(business: @business, today: @today).call
    candidate = result.created.find { |record| record.metadata.fetch("issue_key") == "supply_gap" || record.metadata.fetch("issue_key") == "asset_missing" }

    assert candidate
    assert_no_match(/要具体化|検索需要があるテーマ/, candidate.title)
    assert_includes %w[data_preparation seo_article], candidate.action_type
    assert_includes %w[supply_gap asset_missing], candidate.metadata.fetch("opportunity_type")
    assert_includes %w[data_operation content_creation], candidate.metadata.fetch("execution_mode")
    assert_equal 1, candidate.metadata.fetch("execution_units").first.fetch("target_amount")
  end

  test "does not create concrete content gap task from active serp queries alone" do
    @business.serp_queries.create!(query: "梅田 喫煙 居酒屋", priority: 10)
    @business.serp_queries.create!(query: "難波 喫煙 カフェ", priority: 20)
    @business.serp_queries.create!(query: "大阪 喫煙可能 飲食店", priority: 30)

    result = MetricActionCandidateGenerator.new(business: @business, today: @today).call

    assert result.created.none? { |candidate| candidate.generation_source == "serp" }
    assert result.created.none? { |candidate| candidate.metadata["source_query"] == "梅田 喫煙 居酒屋" }
  end

  test "does not create serp-backed concrete rank opportunity" do
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

    assert result.created.none? { |candidate| candidate.generation_source == "serp" }
    assert result.created.none? { |candidate| candidate.metadata["source_query"] == keyword || candidate.metadata["serp_keyword"] == keyword }
  end

  test "does not create duplicate analyzer candidate within seven days" do
    create_metric_series(default_impressions: 10, recent_impressions: 1_000, default_clicks: 0, recent_clicks: 5)
    @business.action_candidates.create!(
      title: "CTR0.5%の検索入口を5件書き換える",
      action_type: "seo_improvement",
      generation_source: "business_analyzer",
      evaluation_reason: "business_analyzer:high_impression_low_ctr",
      created_at: @today.to_time
    )

    result = MetricActionCandidateGenerator.new(business: @business, today: @today).call

    assert result.skipped.any? { |reason| reason.include?("high_impression_low_ctr: duplicate") }
    assert_equal 1, @business.action_candidates.where("evaluation_reason LIKE ?", "%business_analyzer:high_impression_low_ctr%").count
  end

  test "saas business also uses generic opportunity analyzer" do
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
    assert result.created.all? { |candidate| candidate.generation_source == "business_analyzer" }
    assert result.created.all? { |candidate| candidate.metadata.dig("opportunity", "opportunity_type").present? }
  end

  test "business analyzer candidates always include opportunity metadata and execution units" do
    @business.serp_queries.create!(query: "梅田 喫煙 居酒屋", priority: 10)
    create_metric_series(
      default_impressions: 10,
      recent_impressions: 1_000,
      default_clicks: 0,
      recent_clicks: 5,
      default_pageviews: 100,
      recent_pageviews: 250,
      default_conversions: 0,
      recent_conversions: 0
    )

    result = MetricActionCandidateGenerator.new(business: @business, today: @today).call
    analyzer_candidates = result.created.select { |candidate| candidate.generation_source == "business_analyzer" }

    assert_not_empty analyzer_candidates
    assert analyzer_candidates.all? { |candidate| candidate.metadata["opportunity_type"].present? }
    assert analyzer_candidates.all? { |candidate| candidate.metadata.dig("opportunity", "opportunity_type").present? }
    assert analyzer_candidates.all? { |candidate| candidate.metadata.dig("decision", "selected", "concrete_task").present? }
    assert analyzer_candidates.all? { |candidate| candidate.metadata.dig("strategy_ranking", "adopted").present? }
    assert analyzer_candidates.all? { |candidate| candidate.metadata["execution_units"].present? }
  end

  test "creates universal concrete candidates when analysis data exists" do
    create_metric_series(
      default_impressions: 20,
      recent_impressions: 50,
      default_clicks: 1,
      recent_clicks: 2,
      default_pageviews: 30,
      recent_pageviews: 40,
      default_conversions: 0,
      recent_conversions: 0
    )

    result = MetricActionCandidateGenerator.new(business: @business, today: @today).call
    issue_keys = result.created.map { |candidate| candidate.metadata.fetch("issue_key") }

    assert_includes issue_keys, "demand_without_supply"
    assert_includes issue_keys, "high_traffic_low_conversion"
    assert_includes issue_keys, "supply_gap"
    result.created.each do |candidate|
      assert_equal "ready", candidate.metadata.fetch("concretization_status")
      assert_no_match(/要具体化|検索需要があるテーマの記事を書く|CV改善|SEO改善|導線改善/, candidate.title)
    end
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

  def create_gsc_import(queries)
    data_source = @business.data_sources.create!(source_type: "gsc", name: "Google Search Console")
    csv = CSV.generate(headers: true) do |rows|
      rows << %w[query clicks impressions ctr position page]
      queries.each_with_index do |query, index|
        rows << [
          query,
          4 + index,
          200 + (index * 30),
          "0.01",
          8 + (index % 8),
          "/articles/#{query.parameterize}"
        ]
      end
    end
    data_source.data_imports.create!(
      filename: "gsc_queries.csv",
      content_type: "text/csv",
      row_count: queries.size,
      processed_text: csv,
      imported_at: @today.to_time
    )
  end
end
