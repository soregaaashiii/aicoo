require "test_helper"

module Aicoo
  class IdeaPipelineTest < ActiveSupport::TestCase
    test "generator creates executable ideas" do
      assert_difference("IdeaPipelineItem.count", 2) do
        result = IdeaPipeline::IdeaGenerator.call(count: 2)
        assert_equal 2, result.created_count
      end

      item = IdeaPipelineItem.last
      assert_equal "idea", item.current_stage
      assert item.problem.present?
      assert item.mvp_concept.present?
    end

    test "scorer stores expected value and score" do
      item = create_item

      IdeaPipeline::IdeaScorer.new(item).call

      assert_equal "scored", item.reload.status
      assert item.final_score.positive?
      assert item.expected_profit_yen.positive?
      assert item.metadata["idea_score"].present?
    end

    test "serp evaluator uses adapter and stores normalized snapshot" do
      item = create_item
      IdeaPipeline::IdeaScorer.new(item).call
      item.update!(final_score: 82)

      stub_serp_adapter(search_result) do
        IdeaPipeline::SerpEvaluator.new(item, provider: "serper", limit: 10).call
      end

      item.reload
      assert_equal "serp_evaluated", item.status
      assert_equal "success", item.serp_snapshot["status"]
      assert item.serp_snapshot["passed"]
      assert_equal 2, item.serp_snapshot["organic_count"]
    end

    test "low score ideas do not run serp" do
      item = create_item
      item.update!(final_score: 40)

      IdeaPipeline::SerpEvaluator.new(item).call

      assert_equal "serp_skipped", item.reload.status
      assert_equal "skipped", item.serp_snapshot["status"]
      assert_equal "score_below_serp_threshold", item.serp_snapshot["reason_code"]
      assert_includes item.serp_snapshot["reason"], "final_scoreが低いためSERPはスキップしました"
      assert item.serp_snapshot["cost_optimization"]
    end

    test "landing page can be generated without serp when score passed" do
      item = create_item
      IdeaPipeline::IdeaScorer.new(item).call
      item.update!(final_score: 82, status: "scored", serp_snapshot: {})

      landing_page = IdeaPipeline::LandingPageBuilder.new(item).call

      assert_equal "draft", landing_page.public_status
      assert_equal landing_page, item.reload.aicoo_lab_landing_page
      assert_equal false, item.metadata.dig("lp_generation", "serp_used")
      assert_equal "serp_pending", item.metadata.dig("lp_generation", "serp_status_at_generation")
      assert_equal "owner_skipped_serp", item.metadata.dig("lp_generation", "reason")
    end

    test "landing page can be generated when serp is not configured" do
      item = create_item
      item.update!(
        status: "serp_not_configured",
        final_score: 20,
        serp_snapshot: { "status" => "blocked", "reason" => "API Key未設定" }
      )

      assert_difference("AicooLabLandingPage.count", 1) do
        IdeaPipeline::LandingPageBuilder.new(item).call
      end

      assert_equal "serp_not_configured", item.reload.metadata.dig("lp_generation", "serp_status_at_generation")
      assert_equal false, item.metadata.dig("lp_generation", "serp_used")
    end

    test "landing page generated without serp can be published" do
      item = create_item
      item.update!(status: "owner_approved", final_score: 50, serp_snapshot: {})

      landing_page = IdeaPipeline::LandingPageBuilder.new(item).call
      IdeaPipeline::Publisher.new(item).call

      assert_equal "published", landing_page.reload.public_status
      assert_equal "published", item.reload.status
    end

    test "landing page can be generated when owner approved without serp" do
      item = create_item
      item.update!(status: "owner_approved", final_score: 40, serp_snapshot: {})

      assert_difference("AicooLabLandingPage.count", 1) do
        IdeaPipeline::LandingPageBuilder.new(item).call
      end
    end

    test "landing page can be generated when low score serp is skipped after owner approval" do
      item = create_item
      item.update!(status: "owner_approved", final_score: 40)

      IdeaPipeline::SerpEvaluator.new(item).call

      assert_equal "serp_skipped", item.reload.status
      assert_equal "score_below_serp_threshold", item.serp_snapshot["reason_code"]
      assert_includes item.serp_warning_for_lp_generation, "承認済みのためLP生成は可能です"
      assert_difference("AicooLabLandingPage.count", 1) do
        IdeaPipeline::LandingPageBuilder.new(item).call
      end
    end

    test "landing page can be generated when serp skipped" do
      item = create_item
      item.update!(status: "serp_skipped", final_score: 30, serp_snapshot: { "status" => "skipped" })

      assert_difference("AicooLabLandingPage.count", 1) do
        IdeaPipeline::LandingPageBuilder.new(item).call
      end
    end

    test "blocked idea statuses cannot generate landing page" do
      %w[rejected archived duplicate unsafe].each do |status|
        item = create_item
        item.update!(status:, final_score: 90)

        error = assert_raises(ArgumentError) { IdeaPipeline::LandingPageBuilder.new(item).call }
        assert_equal status, item.lp_generation_block_reason
        assert error.message.present?
      end
    end

    test "already converted idea cannot generate another landing page" do
      item = create_item
      item.update!(status: "owner_approved", final_score: 90)
      IdeaPipeline::LandingPageBuilder.new(item).call

      error = assert_raises(ArgumentError) { IdeaPipeline::LandingPageBuilder.new(item.reload).call }

      assert_equal "already_converted", item.lp_generation_block_reason
      assert_includes error.message, "すでにLP生成済み"
    end

    test "fallback failure reason is never blank" do
      item = create_item
      item.update!(status: "idea", final_score: nil, serp_snapshot: {})

      assert item.lp_generation_failure_reason.present?
      assert_includes item.lp_generation_debug_context[:generation_conditions], "SERP未実行"
    end

    test "landing page publication learning and mvp spec flow" do
      item = create_item
      IdeaPipeline::IdeaScorer.new(item).call
      item.update!(
        final_score: 82,
        serp_snapshot: {
          "passed" => true,
          "query" => "地域 チェックリスト",
          "competition_strength" => 30,
          "market_signal" => 70,
          "differentiation_score" => 76
        }
      )

      landing_page = IdeaPipeline::LandingPageBuilder.new(item).call

      assert_equal "draft", landing_page.public_status
      assert_equal landing_page, item.reload.aicoo_lab_landing_page
      assert_not_includes landing_page.headline, "LP実験"
      assert_not_includes landing_page.body, "SERP検証"
      assert_not_includes landing_page.body, "AICOO"
      assert_not_includes landing_page.body, "Target user"

      IdeaPipeline::Publisher.new(item).call
      assert_equal "published", landing_page.reload.public_status
      item.reload
      assert item.business
      assert_equal item.business, landing_page.reload.business
      assert_equal "idea_pipeline", item.business.source
      assert_equal item.id, item.business.idea_id
      assert item.business.created_by_aicoo?
      assert item.business.launched?
      assert item.business.daily_run_enabled?
      assert item.business.serp_enabled?

      3.times { landing_page.aicoo_lab_landing_page_events.create!(event_type: "view") }
      landing_page.aicoo_lab_landing_page_events.create!(event_type: "cta_click")

      IdeaPipeline::LearningEvaluator.new(item).call
      IdeaPipeline::MvpSpecBuilder.new(item).call

      item.reload
      assert item.learning_snapshot["pv"].positive?
      assert_includes IdeaPipelineItem::MVP_DECISIONS, item.mvp_decision
      assert item.mvp_specification.present? if item.mvp_decision == "develop"
    end

    test "mvp completion creates business when lp is not published" do
      item = create_item
      item.update!(final_score: 70, learning_snapshot: { "recommendation" => "continue_lp" })

      assert_difference("Business.count", 1) do
        IdeaPipeline::MvpSpecBuilder.new(item).call
      end

      item.reload
      assert_equal "continuing", item.status
      assert_equal "continue_lp", item.mvp_decision
      assert item.business
      assert_equal "idea_pipeline", item.business.source
      assert_equal item.id, item.business.idea_id
      assert item.business.launched?
      assert_includes Business.real_businesses, item.business
    end

    test "business linker repairs published pipeline landing page without business" do
      item = create_item
      item.update!(status: "owner_approved", final_score: 75)
      landing_page = IdeaPipeline::LandingPageBuilder.new(item).call
      landing_page.update!(
        status: "published",
        public_status: "published",
        published_at: Time.current,
        published_slug: "pipeline-repair-test"
      )
      item.update!(business: nil)

      assert_difference("Business.count", 1) do
        Aicoo::IdeaPipeline::BusinessLinker.new(item).call
      end

      assert_equal item.reload.business, landing_page.reload.business
      assert item.business.launched?
    end

    private

    def create_item
      IdeaPipelineItem.create!(
        title: "地域チェックリストLP",
        short_description: "地域検索向けの比較前チェックリスト",
        problem: "候補が多く判断しづらい",
        target_user: "地域名で検索するユーザー",
        revenue_model: "送客と問い合わせ",
        mvp_concept: "1地域1LPで反応を見る",
        lp_concept: "選び方とチェック項目を提示する",
        difficulty_score: 30,
        development_hours: 8,
        ai_implementation_score: 80
      )
    end

    def search_result
      Aicoo::Serp::SearchResult.new(
        provider: "serper",
        type: "google_search",
        query: "地域 チェックリスト",
        location: "Japan",
        language: "ja",
        fetched_at: Time.current.iso8601,
        organic_results: [
          { position: 1, title: "比較サービス", url: "https://example.com/1", displayed_url: "example.com", snippet: "比較できます", source: "serper", raw: {} },
          { position: 2, title: "チェックリスト", url: "https://example.com/2", displayed_url: "example.com", snippet: "確認できます", source: "serper", raw: {} }
        ],
        people_also_ask: [ { question: "どう選ぶ？" } ],
        related_searches: [ "地域 比較", "地域 おすすめ" ],
        ai_overview: nil,
        raw_response: {}
      )
    end

    def stub_serp_adapter(result)
      singleton = class << Aicoo::Serp::Adapter; self; end
      original_call = Aicoo::Serp::Adapter.method(:call)
      singleton.define_method(:call) { |**_kwargs| result }
      yield
    ensure
      singleton.define_method(:call) { |**kwargs| original_call.call(**kwargs) }
    end
  end
end
