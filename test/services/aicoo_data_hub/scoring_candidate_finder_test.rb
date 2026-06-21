require "test_helper"

module AicooDataHub
  class ScoringCandidateFinderTest < ActiveSupport::TestCase
    test "finds running lab experiment with landing page snapshot" do
      experiment = create_experiment(title: "DataHub scoring lab", status: "running")
      landing_page = create_landing_page(experiment)
      AicooDataSnapshot.create!(
        source_type: "landing_page",
        source_id: landing_page.id,
        payload: {
          experiment_id: experiment.id,
          pv: 120,
          cta_click: 12,
          signup: 3
        }
      )

      candidates = ScoringCandidateFinder.new.call
      candidate = candidates.find { |item| item.target_type == "lab_experiment" }

      assert_not_nil candidate
      assert_equal experiment.id, candidate.target_id
      assert_equal "DataHub scoring lab", candidate.title
      assert_includes candidate.reason, "running"
      assert_equal 120, candidate.available_metrics[:pv]
      assert_includes candidate.suggested_action_url, "/admin/aicoo_lab/scoring_queue/#{experiment.id}/30/snapshot"
    end

    test "finds done revenue execution with snapshot and no actual result" do
      execution = create_revenue_execution(
        title: "DataHub scoring revenue",
        status: "done",
        actual_90d_profit_yen: nil
      )
      AicooDataSnapshot.create!(
        source_type: "revenue_execution",
        source_id: execution.id,
        payload: {
          predicted_value: 10_000,
          actual_90d_profit_yen: nil,
          calibration_score: nil
        }
      )

      candidates = ScoringCandidateFinder.new.call
      candidate = candidates.find { |item| item.target_type == "revenue_execution" }

      assert_not_nil candidate
      assert_equal execution.id, candidate.target_id
      assert_equal "DataHub scoring revenue", candidate.title
      assert_includes candidate.reason, "実績90日利益が未入力"
      assert_equal 10_000, candidate.available_metrics[:predicted_value]
      assert_includes candidate.suggested_action_url, "/admin/aicoo_revenue/executions/#{execution.id}/edit"
    end

    test "does not find revenue execution with actual result" do
      execution = create_revenue_execution(
        title: "DataHub scored revenue",
        status: "done",
        actual_90d_profit_yen: 8_000
      )
      AicooDataSnapshot.create!(
        source_type: "revenue_execution",
        source_id: execution.id,
        payload: {
          predicted_value: 10_000,
          actual_90d_profit_yen: 8_000,
          calibration_score: 80.0
        }
      )

      candidates = ScoringCandidateFinder.new.call

      assert_empty candidates.select { |item| item.target_type == "revenue_execution" }
    end

    private

    def create_experiment(attributes = {})
      AicooLabExperiment.create!(
        {
          title: "DataHub scoring experiment",
          experiment_type: "lp",
          acquisition_channel: "seo"
        }.merge(attributes)
      )
    end

    def create_landing_page(experiment)
      experiment.create_aicoo_lab_landing_page!(
        headline: "DataHub scoring headline",
        subheadline: "DataHub scoring subheadline",
        body: "DataHub scoring body",
        cta_text: "事前登録する"
      )
    end

    def create_revenue_execution(attributes = {})
      AicooRevenueExecution.create!(
        {
          source_type: "candidate",
          source_id: 1,
          title: "DataHub scoring revenue",
          expected_90d_profit_yen: 50_000,
          success_probability: 0.2,
          revenue_total_value_yen: 10_000,
          estimated_work_minutes: 60,
          budget_yen: 0,
          revenue_score: 10,
          status: "done"
        }.merge(attributes)
      )
    end
  end
end
