require "test_helper"

module Admin
  module AicooLab
    class ApprovedExperimentsControllerTest < ActionDispatch::IntegrationTest
      test "shows approved not started experiments" do
        experiment = create_approved_experiment(title: "Approved visible")

        get admin_aicoo_lab_approved_experiments_url

        assert_response :success
        assert_includes response.body, experiment.title
        assert_includes response.body, "承認済み未開始"
        assert_includes response.body, "検証中にしても自動で集客されるわけではありません"
        assert_includes response.body, "検証開始待ち"
        assert_includes response.body, "承認済み"
      end

      test "shows approved approval pending experiments as not started" do
        experiment = create_approved_experiment(
          title: "Approved approval pending visible",
          status: "approval_pending",
          approval_status: "approved"
        )

        get admin_aicoo_lab_approved_experiments_url

        assert_response :success
        assert_includes response.body, experiment.title
        assert_includes response.body, "承認待ち"
        assert_includes response.body, "検証開始待ち"
      end

      test "moves approved experiment to running and sets dates" do
        experiment = create_approved_experiment(title: "Start single")
        travel_to Time.zone.local(2026, 6, 18, 10, 0, 0) do
          patch admin_aicoo_lab_approved_experiment_running_url(experiment)
        end

        experiment.reload
        assert_redirected_to admin_aicoo_lab_experiment_url(experiment)
        assert_equal "running", experiment.status
        assert_equal Time.zone.local(2026, 6, 18, 10, 0, 0), experiment.started_at
        assert_equal Time.zone.local(2026, 6, 18, 10, 0, 0), experiment.published_at
        assert_equal Time.zone.local(2026, 6, 25, 10, 0, 0), experiment.score_due_7d_at
        assert_equal Time.zone.local(2026, 7, 18, 10, 0, 0), experiment.score_due_30d_at
        assert_equal Time.zone.local(2026, 9, 16, 10, 0, 0), experiment.score_due_90d_at
      end

      test "bulk moves approved experiments to running" do
        first_experiment = create_approved_experiment(title: "Bulk start 1")
        second_experiment = create_approved_experiment(title: "Bulk start 2")

        post admin_aicoo_lab_approved_experiments_bulk_running_url,
             params: { experiment_ids: [ first_experiment.id, second_experiment.id ] }

        assert_redirected_to admin_aicoo_lab_approved_experiments_url
        assert_equal "running", first_experiment.reload.status
        assert first_experiment.started_at.present?
        assert_equal "running", second_experiment.reload.status
        assert second_experiment.score_due_90d_at.present?
      end

      private

      def create_approved_experiment(attributes = {})
        AicooLabExperiment.create!(
          {
            title: "Approved experiment",
            description: "Approved experiment description",
            experiment_type: "lp",
            market_category: "approved market",
            acquisition_channel: "seo",
            status: "preview_ready",
            approval_status: "approved",
            expected_90d_profit_yen: 50_000,
            success_probability: 0.3,
            budget_yen: 0,
            estimated_work_minutes: 60
          }.merge(attributes)
        )
      end
    end
  end
end
