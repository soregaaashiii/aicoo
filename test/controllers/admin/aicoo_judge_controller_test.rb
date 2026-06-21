require "test_helper"

module Admin
  class AicooJudgeControllerTest < ActionDispatch::IntegrationTest
    test "shows judge dashboard" do
      create_lab_metric(source: "lab", predicted: 10_000, actual: 8_000)
      create_revenue_execution(source: "revenue", predicted: 10_000, actual: 9_000)

      get admin_aicoo_judge_url

      assert_response :success
      assert_includes response.body, "成績表"
      assert_includes response.body, "この画面でやること"
      assert_includes response.body, "採点済み予測数"
      assert_includes response.body, "現在最も当たる予測者"
      assert_includes response.body, "今日やること"
      assert_includes response.body, "予測者ランキング"
      assert_includes response.body, "予測精度推移JSON"
      assert_includes response.body, "average_calibration_score"
      assert_includes response.body, "行動候補の予測精度"
      assert_includes response.body, admin_aicoo_judge_action_predictions_path
    end

    test "shows action prediction judge dashboard" do
      action_candidate = ActionCandidate.create!(
        business: businesses(:suelog),
        title: "Judge action prediction",
        action_type: "seo_improvement",
        generation_source: "ai_business",
        immediate_value_yen: 10_000,
        success_probability: 1,
        evaluation_reason: "metric_rule:ctr_improvement"
      )
      ActionResult.create!(
        action_candidate:,
        business: action_candidate.business,
        executed_on: Date.current - 10,
        evaluated_on: Date.current,
        actual_profit_yen: 8_000,
        evaluation_status: "evaluated"
      )

      get admin_aicoo_judge_action_predictions_url(generation_source: "ai_business")

      assert_response :success
      assert_includes response.body, "行動候補の予測精度"
      assert_includes response.body, "generation_source別サマリー"
      assert_includes response.body, "Business別サマリー"
      assert_includes response.body, "action_type別サマリー"
      assert_includes response.body, "metric_rule別サマリー"
      assert_includes response.body, "ctr_improvement"
      assert_includes response.body, "ai_business"
    end

    test "shows action prediction judge dashboard from short judge route" do
      get judge_action_predictions_url

      assert_response :success
      assert_includes response.body, "行動候補の予測精度"
    end

    private

    def create_lab_metric(source:, predicted:, actual:)
      experiment = AicooLabExperiment.create!(title: "Judge controller #{source}", experiment_type: "lp", acquisition_channel: "seo")
      prediction = experiment.aicoo_lab_predictions.create!(
        prediction_type: "profit",
        prediction_source: source,
        target_days: 90,
        predicted_value: predicted,
        predicted_value_unit: "yen"
      )
      result = experiment.aicoo_lab_results.create!(
        result_type: "profit",
        target_days: 90,
        actual_value: actual,
        actual_value_unit: "yen",
        sample_size: 100
      )

      AicooLabErrorMetric.create!(aicoo_lab_prediction: prediction, aicoo_lab_result: result)
    end

    def create_revenue_execution(source:, predicted:, actual:)
      AicooRevenueExecution.create!(
        source_type: "candidate",
        source_id: AicooRevenueExecution.maximum(:source_id).to_i + 1,
        title: "Judge controller revenue #{source}",
        expected_90d_profit_yen: predicted,
        success_probability: 1,
        revenue_total_value_yen: predicted,
        estimated_work_minutes: 60,
        budget_yen: 0,
        revenue_score: 10,
        status: "done",
        prediction_source: source,
        actual_90d_profit_yen: actual
      )
    end
  end
end
