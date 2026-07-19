require "test_helper"
require "ostruct"

module Aicoo
  class TodayActionBoardArticleOpportunityTest < ActiveSupport::TestCase
    setup do
      @business = businesses(:suelog)
      ActionCandidate.update_all(status: "archived")
    end

    test "article opportunity candidates are ordered by expected improvement score" do
      low = create_article_opportunity_candidate!(
        title: "低い記事改善",
        article_id: 101,
        expected_improvement_score: 2.0,
        search_demand_score: 1.8,
        improvement_potential_score: 4.0
      )
      high = create_article_opportunity_candidate!(
        title: "高い記事改善",
        article_id: 102,
        expected_improvement_score: 9.0,
        search_demand_score: 1.2,
        improvement_potential_score: 3.0
      )

      items = TodayActionBoard.new(mode: "revenue", per_page: 100).call.items

      assert_operator item_index(items, high), :<, item_index(items, low)
      high_item = items.find { |item| item.record == high }
      assert_equal 9.0.to_d, high_item.expected_improvement_score
      assert_equal "CTR改善", high_item.improvement_type_label
      assert_equal false, high_item.codex_target
      assert_equal false, high_item.auto_execution
    end

    test "article opportunity suppresses same article legacy candidate" do
      legacy = create_legacy_article_candidate!(
        title: "旧Analyzerの記事改善",
        article_id: 201,
        opportunity_type: "ctr_improvement",
        immediate_value_yen: 900_000
      )
      current = create_article_opportunity_candidate!(
        title: "新Analyzerの記事改善",
        article_id: 201,
        opportunity_type: "ctr_improvement",
        expected_improvement_score: 3.0
      )

      items = TodayActionBoard.new(mode: "revenue", per_page: 100).call.items

      assert_includes items.map(&:record), current
      assert_not_includes items.map(&:record), legacy
      assert_equal "duplicate_suppressed_by_article_opportunity", legacy.reload.metadata["today_exclusion_reason"]
    end

    test "archived article opportunity candidate is not shown unconditionally" do
      archived = create_article_opportunity_candidate!(
        title: "Archived ArticleOpportunity",
        article_id: 301,
        status: "archived",
        expected_improvement_score: 99.0
      )

      items = TodayActionBoard.new(mode: "revenue", per_page: 100).call.items

      assert_not_includes items.map(&:record), archived
    end

    test "connector does not promote comparison-only archived candidates" do
      comparison = create_article_opportunity_candidate!(
        title: "比較用ArticleOpportunity",
        article_id: 350,
        status: "archived",
        expected_improvement_score: 99.0
      )
      comparison.update_columns(
        metadata: comparison.metadata.merge(
          "experimental_only" => true,
          "production_candidate" => false,
          "archived_reason" => "article_opportunity_analyzer_comparison_only"
        )
      )

      analyzer_result = OpenStruct.new(article_results: [], action_candidate_count: 0)
      Aicoo::ArticleOpportunityAnalyzer.stub(:from_snapshots, analyzer_result) do
        result = ArticleOpportunityTodayConnector.new(business: @business, apply: true).call

        assert_equal 0, result.activated_count
      end
      assert_equal "archived", comparison.reload.status
    end

    test "legacy article candidate remains fallback when no active article opportunity exists" do
      legacy = create_legacy_article_candidate!(
        title: "旧Analyzer fallback",
        article_id: 401,
        opportunity_type: "ctr_improvement",
        immediate_value_yen: 10_000
      )

      items = TodayActionBoard.new(mode: "revenue", per_page: 100).call.items

      assert_includes items.map(&:record), legacy
    end

    private

    def create_article_opportunity_candidate!(attributes = {})
      article_id = attributes.fetch(:article_id, 100)
      opportunity_type = attributes.fetch(:opportunity_type, "ctr_improvement")
      ActionCandidate.create!(
        business: @business,
        title: attributes.fetch(:title, "ArticleOpportunity記事改善"),
        status: attributes.fetch(:status, "proposal"),
        action_type: "article_update",
        generation_source: "business_analyzer",
        immediate_value_yen: 0,
        expected_hours: attributes.fetch(:estimated_work_hours, 0.3),
        success_probability: attributes.fetch(:success_probability, 0.55),
        metadata: {
          "value_model_name" => TodayActionBoard::ARTICLE_OPPORTUNITY_MODEL_NAME,
          "analysis_source" => "article_analytics_snapshot",
          "snapshot_id" => attributes.fetch(:snapshot_id, article_id),
          "article_id" => article_id,
          "article_path" => "/articles/article-#{article_id}",
          "opportunity_type" => opportunity_type,
          "opportunity_label" => "CTR改善",
          "expected_improvement_score" => attributes.fetch(:expected_improvement_score, 5.0),
          "search_demand_score" => attributes.fetch(:search_demand_score, 1.0),
          "improvement_potential_score" => attributes.fetch(:improvement_potential_score, 5.0),
          "success_probability" => attributes.fetch(:success_probability, 0.55),
          "estimated_work_hours" => attributes.fetch(:estimated_work_hours, 0.3),
          "business_value" => attributes.fetch(:business_value, 1.3),
          "ranking_reason" => "ArticleOpportunityAnalyzerで評価しました。",
          "action_plan" => {
            "summary" => attributes.fetch(:title, "ArticleOpportunity記事改善"),
            "target" => "/articles/article-#{article_id}",
            "owner_next_step" => "タイトルを見直す",
            "execution_steps" => [ "タイトルを見直す" ]
          }
        }
      )
    end

    def create_legacy_article_candidate!(attributes = {})
      article_id = attributes.fetch(:article_id, 100)
      ActionCandidate.create!(
        business: @business,
        title: attributes.fetch(:title, "旧Analyzer記事改善"),
        status: "proposal",
        action_type: "article_update",
        generation_source: "business_analyzer",
        immediate_value_yen: attributes.fetch(:immediate_value_yen, 20_000),
        expected_hours: 1,
        success_probability: 0.7,
        metadata: {
          "article_id" => article_id,
          "article_path" => "/articles/article-#{article_id}",
          "opportunity_type" => attributes.fetch(:opportunity_type, "ctr_improvement"),
          "execution_mode" => "manual_operation",
          "concrete_task" => attributes.fetch(:title, "旧Analyzer記事改善"),
          "action_plan" => {
            "summary" => attributes.fetch(:title, "旧Analyzer記事改善"),
            "target" => "/articles/article-#{article_id}",
            "owner_next_step" => "記事を確認する",
            "execution_steps" => [ "記事を確認する" ]
          }
        }
      )
    end

    def item_index(items, candidate)
      items.index { |item| item.record == candidate }
    end
  end
end
