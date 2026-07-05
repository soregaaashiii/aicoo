require "test_helper"

module Aicoo
  class ActionDecisionEngineTest < ActiveSupport::TestCase
    setup do
      @business = businesses(:cards)
      @business.update!(
        name: "Generic Test Business",
        metadata: {
          "capabilities" => {
            "has_articles" => true,
            "has_lp" => true,
            "conversion_events" => [ "signup" ],
            "assets" => [
              {
                "asset_type" => "articles",
                "can_create" => true,
                "can_update" => true,
                "estimated_minutes" => 90,
                "historical_success_rate" => 0.45,
                "expected_roi" => 1.4,
                "required_data" => [ "gsc" ]
              },
              {
                "asset_type" => "comparison_pages",
                "can_create" => true,
                "can_update" => true,
                "estimated_minutes" => 60,
                "historical_success_rate" => 0.55,
                "expected_roi" => 2.0,
                "required_data" => [ "gsc", "serp" ]
              },
              {
                "asset_type" => "landing_pages",
                "can_create" => true,
                "can_update" => true,
                "estimated_minutes" => 120,
                "historical_success_rate" => 0.35,
                "expected_roi" => 1.2,
                "required_data" => [ "ga4" ]
              }
            ]
          }
        }
      )
    end

    test "enumerates actions from opportunity and business knowledge" do
      decision = Aicoo::ActionDecisionEngine.call(
        opportunity_for(
          opportunity_type: "demand_without_asset",
          target: { "label" => "「Vault 名刺管理 比較」", "query" => "Vault 名刺管理 比較" }
        )
      )

      assert decision.valid?
      assert_includes decision.candidates.map(&:asset_type), "articles"
      assert_includes decision.candidates.map(&:asset_type), "comparison_pages"
      assert_equal "comparison_pages", decision.selected.asset_type
      assert_equal "「Vault 名刺管理 比較」向けの比較ページを1本作成する", decision.concrete_task
      assert_no_match(/検索需要があるテーマ/, decision.concrete_task)
      assert_equal "content_creation", decision.execution_mode
    end

    test "uses expected value time success rate and roi to choose the best action" do
      decision = Aicoo::ActionDecisionEngine.call(
        opportunity_for(
          opportunity_type: "demand_without_asset",
          target: { "label" => "「料金 比較」", "query" => "料金 比較" },
          expected_value_yen: 10_000,
          expected_hours: 2,
          success_probability: 0.4
        )
      )

      selected = decision.selected

      assert_equal "comparison_pages", selected.asset_type
      assert selected.expected_profit_yen > 10_000
      assert_operator selected.score, :>, 0
      assert_equal "low", selected.risk
    end

    test "conversion gap becomes a concrete cta action" do
      @business.update!(
        metadata: {
          "capabilities" => {
            "has_lp" => true,
            "conversion_events" => [ "signup" ],
            "assets" => [
              {
                "asset_type" => "cta",
                "can_create" => true,
                "can_update" => true,
                "estimated_minutes" => 30,
                "historical_success_rate" => 0.5,
                "expected_roi" => 1.8
              },
              {
                "asset_type" => "internal_links",
                "can_create" => true,
                "can_update" => true,
                "estimated_minutes" => 50,
                "historical_success_rate" => 0.35,
                "expected_roi" => 1.2
              }
            ]
          }
        }
      )

      decision = Aicoo::ActionDecisionEngine.call(
        opportunity_for(
          opportunity_type: "traffic_without_conversion",
          target: { "label" => "流入上位ページ", "amount" => 5 },
          required_resources: { "conversion_events" => [ "signup" ] }
        )
      )

      assert decision.valid?
      assert_equal "cta", decision.selected.asset_type
      assert_equal "流入上位5ページにsignup導線を追加する", decision.concrete_task
      assert_equal "code_revision", decision.execution_mode
    end

    private

    def opportunity_for(opportunity_type:, target:, expected_value_yen: 20_000, expected_hours: 1.5, success_probability: 0.4, required_resources: {})
      issue = Aicoo::BusinessAnalyzers::BaseAnalyzer::Issue.new(
        key: opportunity_type,
        title: "Analyzer intermediate result",
        description: "Intermediate analysis",
        action_type: "seo_improvement",
        quantity: target["amount"] || 1,
        unit: "件",
        why: "データ上の改善余地があるため",
        expected_effect: "期待効果あり",
        expected_value_yen:,
        success_probability:,
        strategic_value_score: 40,
        risk_reduction_score: 20,
        expected_hours:,
        confidence_score: 50,
        metadata: { "opportunity_type" => opportunity_type, "target_identifier" => target["label"] }
      )

      Aicoo::OpportunityEngine::Opportunity.new(
        key: opportunity_type,
        business: @business,
        source_analyzer: "test",
        opportunity_type:,
        target:,
        reason: issue.why,
        expected_value_yen:,
        expected_hours:,
        success_probability:,
        confidence: 50,
        execution_mode: "content_creation",
        required_resources:,
        supporting_metrics: { "source" => [ "gsc" ] },
        source_issue: issue
      )
    end
  end
end
