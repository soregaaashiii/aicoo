require "test_helper"

module Admin
  module AicooLab
    class ScoringQueueControllerTest < ActionDispatch::IntegrationTest
      test "shows due running experiments" do
        experiment = create_running_experiment(title: "Due scoring", score_due_7d_at: 1.hour.ago)

        get admin_aicoo_lab_scoring_queue_url

        assert_response :success
        assert_includes response.body, experiment.title
        assert_includes response.body, "採点待ち"
        assert_includes response.body, "ここでは7日/30日/90日の結果を記録します"
      end

      test "does not show experiments before due date" do
        experiment = create_running_experiment(title: "Not due scoring", score_due_7d_at: 1.day.from_now)

        get admin_aicoo_lab_scoring_queue_url

        assert_response :success
        assert_not_includes response.body, experiment.title
      end

      test "creates scoring results and marks scored date" do
        experiment = create_running_experiment(title: "Create scoring", score_due_7d_at: 1.hour.ago)
        landing_page = create_landing_page_with_events(experiment, views: 4, clicks: 2, signups: 1)

        assert_difference("AicooLabResult.count", 3) do
          post admin_aicoo_lab_scoring_queue_score_url(experiment, 7)
        end

        assert_redirected_to admin_aicoo_lab_scoring_queue_url
        assert experiment.reload.scored_7d_at.present?
        assert_equal 4, experiment.aicoo_lab_results.find_by!(result_type: "pv", target_days: 7).actual_value.to_i
        assert_equal 50, experiment.aicoo_lab_results.find_by!(result_type: "ctr", target_days: 7).actual_value.to_i
        assert_equal landing_page.view_count, experiment.aicoo_lab_results.first.sample_size
      end

      test "shows datahub snapshot scoring confirmation without saving" do
        experiment = create_running_experiment(title: "Snapshot confirmation", score_due_30d_at: 1.hour.ago)
        landing_page = create_landing_page_with_events(experiment, views: 0)
        create_landing_page_snapshot(landing_page, pv: 20, cta_click: 4, signup: 2)

        assert_no_difference("AicooLabResult.count") do
          get admin_aicoo_lab_scoring_queue_snapshot_url(experiment, 30)
        end

        assert_response :success
        assert_includes response.body, "実績データを確認して採点"
        assert_includes response.body, "PV"
        assert_includes response.body, "20"
        assert_includes response.body, "CTAクリック"
        assert_includes response.body, "Signup"
        assert_includes response.body, "サンプル数"
        assert_includes response.body, "最低サンプル到達"
        assert_includes response.body, "この値で採点作成"
      end

      test "creates scoring results from datahub snapshot after confirmation" do
        experiment = create_running_experiment(title: "Snapshot scoring", score_due_30d_at: 1.hour.ago)
        landing_page = create_landing_page_with_events(experiment, views: 0)
        create_landing_page_snapshot(landing_page, pv: 20, cta_click: 5, signup: 2)

        assert_difference("AicooLabResult.count", 3) do
          post admin_aicoo_lab_scoring_queue_score_snapshot_url(experiment, 30)
        end

        assert_redirected_to admin_aicoo_lab_scoring_queue_url
        assert experiment.reload.scored_30d_at.present?
        assert_equal 20, experiment.aicoo_lab_results.find_by!(result_type: "pv", target_days: 30).actual_value.to_i
        assert_equal 25, experiment.aicoo_lab_results.find_by!(result_type: "ctr", target_days: 30).actual_value.to_i
        assert_equal 10, experiment.aicoo_lab_results.find_by!(result_type: "conversion_rate", target_days: 30).actual_value.to_i
      end

      test "recalculates error metrics when matching prediction exists" do
        experiment = create_running_experiment(title: "Metric scoring", score_due_7d_at: 1.hour.ago)
        create_landing_page_with_events(experiment, views: 4)
        experiment.aicoo_lab_predictions.create!(
          prediction_type: "pv",
          target_days: 7,
          predicted_value: 5,
          predicted_value_unit: "count"
        )

        assert_difference("AicooLabErrorMetric.count", 1) do
          post admin_aicoo_lab_scoring_queue_score_url(experiment, 7)
        end
      end

      test "ninety day scoring is formal even below sample threshold" do
        experiment = create_running_experiment(
          title: "Formal 90d scoring",
          score_due_90d_at: 1.hour.ago,
          sample_pv_threshold: 1_000,
          current_pv: 10
        )
        create_landing_page_with_events(experiment, views: 10)

        post admin_aicoo_lab_scoring_queue_score_url(experiment, 90)

        result = experiment.aicoo_lab_results.find_by!(result_type: "pv", target_days: 90)
        assert result.is_formal_score
        assert_not result.sample_threshold_reached
        assert_equal 10, result.sample_size
        assert experiment.reload.scored_90d_at.present?
      end

      private

      def create_running_experiment(attributes = {})
        AicooLabExperiment.create!(
          {
            title: "Running scoring",
            experiment_type: "lp",
            acquisition_channel: "seo",
            status: "running",
            approval_status: "approved",
            expected_90d_profit_yen: 50_000,
            success_probability: 0.3,
            sample_pv_threshold: 1_000,
            current_pv: 0,
            published_at: 10.days.ago,
            started_at: 10.days.ago
          }.merge(attributes)
        )
      end

      def create_landing_page_with_events(experiment, views:, clicks: 0, signups: 0)
        landing_page = experiment.create_aicoo_lab_landing_page!(
          headline: "#{experiment.title} headline",
          subheadline: "Scoring subheadline",
          body: "Scoring body",
          cta_text: "事前登録する",
          status: "preview_ready"
        )
        views.times { landing_page.aicoo_lab_landing_page_events.create!(event_type: "view") }
        clicks.times { landing_page.aicoo_lab_landing_page_events.create!(event_type: "cta_click") }
        signups.times { |index| landing_page.aicoo_lab_signups.create!(email: "scoring-#{index}@example.com") }
        landing_page
      end

      def create_landing_page_snapshot(landing_page, pv:, cta_click:, signup:)
        AicooDataSnapshot.create!(
          source_type: "landing_page",
          source_id: landing_page.id,
          payload: {
            experiment_id: landing_page.aicoo_lab_experiment_id,
            pv:,
            cta_click:,
            signup:,
            cta_rate: cta_click.to_d / pv,
            signup_rate: signup.to_d / pv,
            sample_threshold_reached: false
          }
        )
      end
    end
  end
end
