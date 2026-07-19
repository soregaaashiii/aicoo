require "test_helper"
require "set"

module Aicoo
  class TodayLearningReflectionDiagnosticTest < ActiveSupport::TestCase
    setup do
      @business = businesses(:suelog)
      ActionCandidate.update_all(status: "archived")
    end

    test "evaluated candidate is reported as already executed instead of being forced into Today" do
      candidate = create_candidate!
      ActionPredictionCalibration.create!(
        action_type: "article_opportunity:ctr_improvement",
        sample_count: 12,
        profit_calibration_factor: 1.1,
        probability_calibration_factor: 1.0,
        confidence_level: "medium",
        warning_level: "none",
        approval_status: "auto_applied"
      )
      ActionResult.create!(
        action_candidate: candidate,
        business: @business,
        executed_on: Date.yesterday,
        evaluated_on: Date.current,
        evaluation_status: "evaluated",
        actual_revenue_yen: 1_000,
        actual_profit_yen: 800,
        metadata: {
          "activity_learning_pipeline" => {
            "auto_generated" => true
          }
        }
      )

      result = TodayLearningReflectionDiagnostic.new(candidate_id: candidate.id).call

      assert result.candidate_exists
      assert result.already_executed
      assert result.learning_applied
      assert result.expected_value_updated
      assert_not result.today_eligible
      assert_equal "already_executed", result.today_exclusion_reason
      assert_not result.included_in_today_board
      assert_equal TodayActionBoard::MODES, result.modes.map(&:mode)
      assert result.modes.all? { |mode| mode.today_exclusion_reason == "already_executed" }
    end

    test "eligible candidate is traced through every Today mode" do
      candidate = create_candidate!(article_id: 902)

      result = TodayLearningReflectionDiagnostic.new(candidate_id: candidate.id).call

      assert result.today_eligible
      assert result.included_in_candidate_items
      assert result.included_in_action_candidate_items
      assert result.included_in_ranking_input
      assert result.included_after_ranking
      assert result.included_in_today_board
      assert_nil result.today_exclusion_reason
      assert result.modes.all?(&:included_in_today_board)
      assert result.modes.all? { |mode| mode.display_position.present? }
    end

    test "missing candidate has a concrete exclusion reason" do
      result = TodayLearningReflectionDiagnostic.new(candidate_id: -1).call

      assert_not result.candidate_exists
      assert_equal "candidate_not_found", result.today_exclusion_reason
      assert_not result.included_in_today_board
    end

    test "activity learning pipeline reports executed Today exclusion precisely" do
      candidate = create_candidate!(article_id: 903)
      ActionResult.create!(
        action_candidate: candidate,
        business: @business,
        executed_on: Date.yesterday,
        evaluated_on: Date.current,
        evaluation_status: "evaluated",
        actual_revenue_yen: 0,
        actual_profit_yen: 0
      )

      stage = ActivityLearningPipelineDiagnostic.new.send(:today_stage, candidate, Set.new)

      assert_equal "WARNING", stage.status
      assert_equal "already_executed", stage.reason
    end

    private

    def create_candidate!(article_id: 901)
      ActionCandidate.create!(
        business: @business,
        title: "学習反映を確認する記事改善",
        status: "proposal",
        action_type: "article_update",
        generation_source: "business_analyzer",
        expected_profit_yen: 20_000,
        expected_hours: 0.5,
        success_probability: 0.6,
        metadata: {
          "value_model_name" => TodayActionBoard::ARTICLE_OPPORTUNITY_MODEL_NAME,
          "analysis_source" => "article_analytics_snapshot",
          "snapshot_id" => article_id,
          "article_id" => article_id,
          "article_path" => "/articles/article-#{article_id}",
          "opportunity_type" => "ctr_improvement",
          "expected_improvement_score" => 8.0,
          "search_demand_score" => 2.0,
          "improvement_potential_score" => 4.0,
          "success_probability" => 0.6,
          "estimated_work_hours" => 0.5,
          "business_value" => 1.2,
          "ranking_reason" => "表示機会がありCTR改善余地があります。",
          "action_plan" => {
            "summary" => "記事タイトルを改善する",
            "target" => "/articles/article-#{article_id}",
            "owner_next_step" => "タイトルを見直す",
            "execution_steps" => [ "タイトルを見直す" ]
          }
        }
      )
    end
  end
end
