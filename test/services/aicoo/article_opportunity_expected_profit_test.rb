require "test_helper"

module Aicoo
  class ArticleOpportunityExpectedProfitTest < ActiveSupport::TestCase
    setup do
      ActionPredictionCalibration.delete_all
      @business = businesses(:suelog)
      @business.update!(
        metadata: @business.metadata.to_h.merge(
          "click_value_yen" => 70,
          "conversion_rate" => 0.03,
          "profit_per_conversion_yen" => 5_000
        )
      )
      @snapshot = AicooDataSnapshot.create!(
        source_type: "article_analytics",
        source_id: 901,
        captured_at: Time.current,
        payload: {
          "business_id" => @business.id,
          "article_id" => 901,
          "normalized_path" => "/articles/umeda-smoking-cafe",
          "gsc" => { "available" => true, "impressions" => 2_400, "clicks" => 18, "ctr" => 0.0075, "average_position" => 13, "query_count" => 5 },
          "ga4" => { "available" => true, "pageviews" => 900, "active_users" => 260, "sessions" => 320, "engagement_seconds" => 24_000 },
          "shop_click" => { "available" => true, "total_clicks" => 12, "article_shop_clicks" => 4, "phone_clicks" => 3, "map_clicks" => 3, "affiliate_clicks" => 2 },
          "learning" => { "improvement_count" => 3, "improvement_success_count" => 2 },
          "snapshot_status" => "active"
        }
      )
    end

    test "ctr opportunity receives grounded yen estimate without fixed multiplier" do
      candidate = create_candidate!("ctr_improvement", expected_improvement_score: 59.3)

      result = ArticleOpportunityExpectedProfit.call(candidate)

      assert_operator result.expected_profit_yen, :>, 0
      assert_not_equal 593_000, result.expected_profit_yen
      assert_not_equal (candidate.metadata["expected_improvement_score"].to_d * 10_000).to_i, result.expected_profit_yen
      assert_operator result.expected_click_gain, :>, 0
      assert_operator result.expected_conversion_gain, :>, 0
      assert_equal "grounded_article_opportunity_profit", result.metadata.dig("expected_profit_model", "value_model")
      assert_includes result.metadata.dig("expected_profit_model", "calibration_update_targets"), "article_opportunity:ctr_improvement"
    end

    test "rank content and internal link opportunities receive expected profit" do
      %w[rank_improvement content_update internal_link_addition].each do |type|
        result = ArticleOpportunityExpectedProfit.call(create_candidate!(type))

        assert_operator result.expected_profit_yen, :>, 0, "#{type} should estimate expected profit"
        assert_operator result.confidence, :>, 0
      end
    end

    test "rank improvement converts rank gain into additional ctr gain" do
      rank = ArticleOpportunityExpectedProfit.call(create_candidate!("rank_improvement"))
      content = ArticleOpportunityExpectedProfit.call(create_candidate!("content_update"))
      diagnostics = rank.metadata.dig("expected_profit_model", "rank_improvement_diagnostics")

      assert_operator rank.expected_ctr_gain, :>, content.expected_ctr_gain
      assert_operator rank.expected_click_gain, :>, content.expected_click_gain
      assert_operator diagnostics["expected_impressions_after_rank_gain"].to_d, :>, diagnostics["current_impressions"].to_d
      assert_operator diagnostics["click_gain_from_impressions"].to_d, :>, 0
      assert_equal diagnostics["total_expected_click_gain"].to_d, rank.expected_click_gain.to_d
    end

    test "rank improvement change does not alter ctr improvement estimate" do
      ctr = ArticleOpportunityExpectedProfit.call(create_candidate!("ctr_improvement"))

      assert_equal 0.035, ctr.expected_ctr_gain
      assert_nil ctr.metadata.dig("expected_profit_model", "rank_improvement_diagnostics")
    end

    test "missing metrics still estimate with initial coefficients and low confidence" do
      candidate = create_candidate!("ctr_improvement", snapshot_id: nil)

      result = ArticleOpportunityExpectedProfit.call(candidate)
      model = result.metadata.fetch("expected_profit_model")

      assert_operator result.expected_profit_yen, :>, 0
      assert_equal "initial_coefficients", result.model_source
      assert_equal true, model["assumption_used"]
      assert_includes model["assumed_fields"], "gsc.impressions"
      assert_equal 0.34, result.confidence
    end

    test "business settings are preferred over initial coefficients" do
      result = ArticleOpportunityExpectedProfit.call(create_candidate!("ctr_improvement"))
      sources = result.metadata.dig("expected_profit_model", "input_sources")

      assert_equal "business_metadata.click_value_yen", sources["click_value_yen"]
      assert_equal "business_metadata.conversion_rate", sources["conversion_rate"]
      assert_equal "business_metadata.profit_per_conversion_yen", sources["profit_per_conversion_yen"]
    end

    test "active calibration adjusts article opportunity estimate" do
      candidate = create_candidate!("ctr_improvement")
      baseline = ArticleOpportunityExpectedProfit.call(candidate)
      ActionPredictionCalibration.create!(
        action_type: "article_opportunity:ctr_improvement",
        sample_count: 12,
        profit_calibration_factor: 2.0,
        probability_calibration_factor: 1.2,
        confidence_level: "medium",
        warning_level: "none",
        approval_status: "auto_applied"
      )

      calibrated = ArticleOpportunityExpectedProfit.call(candidate)

      assert_operator calibrated.expected_revenue_yen, :>, baseline.expected_revenue_yen
      assert_operator calibrated.success_probability, :>, baseline.success_probability
      assert_equal "improvement_type_learning", calibrated.model_source
      assert_equal 0.72, calibrated.confidence
    end

    test "business learning is preferred when enough evaluated results exist" do
      candidate = create_candidate!("ctr_improvement")
      3.times do |index|
        learned_candidate = create_candidate!("ctr_improvement", expected_improvement_score: 8 + index)
        ActionResult.create!(
          action_candidate: learned_candidate,
          business: @business,
          executed_on: 20.days.ago.to_date,
          evaluated_on: 10.days.ago.to_date,
          evaluation_status: "evaluated",
          predicted_expected_profit_yen: 1_000,
          actual_profit_yen: 2_000,
          actual_revenue_yen: 2_000
        )
      end

      result = ArticleOpportunityExpectedProfit.call(candidate)

      assert_equal "business_learning", result.model_source
      assert_equal "business:#{@business.id}:ctr_improvement", result.learning_source
      assert_equal 0.91, result.confidence
    end

    test "business learning coefficients are preferred over initial coefficients" do
      candidate = create_candidate!("ctr_improvement")
      3.times do |index|
        learned_candidate = create_candidate!("ctr_improvement", expected_improvement_score: 8 + index)
        ActionResult.create!(
          action_candidate: learned_candidate,
          business: @business,
          executed_on: 20.days.ago.to_date,
          evaluated_on: 10.days.ago.to_date,
          evaluation_status: "evaluated",
          predicted_expected_profit_yen: 1_000,
          predicted_success_probability: 0.5,
          actual_clicks_delta: 120,
          actual_profit_yen: 60_000,
          actual_revenue_yen: 60_000
        )
      end

      result = ArticleOpportunityExpectedProfit.call(candidate)
      model = result.metadata.fetch("expected_profit_model")

      assert_equal "business_learning", result.model_source
      assert_equal "business_learning", model.dig("input_sources", "ctr_gain_rate")
      assert_operator model.dig("learning_coefficients", "ctr_gain_rate").to_d, :>, 0
      assert_equal 3, model.dig("learning_sample_counts", "business_learning")
    end

    private

    def create_candidate!(opportunity_type, expected_improvement_score: 12.5, snapshot_id: @snapshot.id)
      ActionCandidate.create!(
        business: @business,
        title: "#{opportunity_type} ArticleOpportunity",
        status: "proposal",
        action_type: "article_update",
        generation_source: "business_analyzer",
        expected_hours: 0.3,
        success_probability: 0.55,
        metadata: {
          "value_model_name" => ArticleOpportunityAnalyzer::SnapshotRunner::MODEL_NAME,
          "analysis_source" => "article_analytics_snapshot",
          "snapshot_id" => snapshot_id,
          "article_id" => 901,
          "article_path" => "/articles/umeda-smoking-cafe",
          "opportunity_type" => opportunity_type,
          "expected_improvement_score" => expected_improvement_score,
          "success_probability" => 0.55,
          "estimated_work_hours" => 0.3,
          "business_value" => 1.3
        }
      )
    end
  end
end
