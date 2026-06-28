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

      assert_equal "serp_blocked", item.reload.status
      assert_equal "skipped", item.serp_snapshot["status"]
      assert item.serp_snapshot["cost_optimization"]
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

      IdeaPipeline::Publisher.new(item).call
      assert_equal "published", landing_page.reload.public_status

      3.times { landing_page.aicoo_lab_landing_page_events.create!(event_type: "view") }
      landing_page.aicoo_lab_landing_page_events.create!(event_type: "cta_click")

      IdeaPipeline::LearningEvaluator.new(item).call
      IdeaPipeline::MvpSpecBuilder.new(item).call

      item.reload
      assert item.learning_snapshot["pv"].positive?
      assert_includes IdeaPipelineItem::MVP_DECISIONS, item.mvp_decision
      assert item.mvp_specification.present? if item.mvp_decision == "develop"
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
