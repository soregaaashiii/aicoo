require "test_helper"

module Admin
  module AicooRevenue
    class ExecutionsControllerTest < ActionDispatch::IntegrationTest
      setup do
        AicooLabSetting.current.update!(hourly_cost_yen: 1_200)
      end

      test "creates planned execution from revenue row" do
        candidate = create_candidate(
          title: "Plan revenue execution",
          expected_90d_profit_yen: 100_000,
          success_probability: 0.3,
          neglect_loss_90d_yen: 10_000,
          estimated_work_minutes: 60,
          budget_yen: 0
        )

        assert_difference("AicooRevenueExecution.count") do
          post admin_aicoo_revenue_executions_url, params: execution_params(candidate)
        end

        execution = AicooRevenueExecution.last
        assert_redirected_to admin_aicoo_revenue_executions_url
        assert_equal "planned", execution.status
        assert_equal "candidate", execution.source_type
        assert_equal candidate.id, execution.source_id
        assert_equal candidate.title, execution.title
        assert_equal 100_000, execution.expected_90d_profit_yen
        assert_equal 0.3.to_d, execution.success_probability
        assert_equal 10_000, execution.neglect_loss_90d_yen
        assert_equal 40_000, execution.revenue_total_value_yen
        assert_equal 60, execution.estimated_work_minutes
        assert_equal 0, execution.budget_yen
        assert_equal 40_000.to_d / 1_200, execution.revenue_score
        assert_equal "revenue", execution.prediction_source
        assert_not_nil execution.planned_at
      end

      test "does not create duplicate planned execution for same source" do
        candidate = create_candidate(title: "Duplicate planned revenue execution")

        post admin_aicoo_revenue_executions_url, params: execution_params(candidate)

        assert_no_difference("AicooRevenueExecution.count") do
          post admin_aicoo_revenue_executions_url, params: execution_params(candidate)
        end

        assert_redirected_to admin_aicoo_revenue_executions_url
        assert_equal 1, AicooRevenueExecution.where(source_type: "candidate", source_id: candidate.id, status: "planned").count
      end

      test "shows executions index" do
        AicooRevenueExecution.create!(
          source_type: "candidate",
          source_id: 1,
          title: "Execution index row",
          expected_90d_profit_yen: 50_000,
          success_probability: 0.2,
          revenue_total_value_yen: 10_000,
          estimated_work_minutes: 60,
          budget_yen: 0,
          revenue_score: 10,
          status: "planned"
        )

        get admin_aicoo_revenue_executions_url

        assert_response :success
        assert_includes response.body, "実行記録"
        assert_includes response.body, "Execution index row"
        assert_includes response.body, "予測者"
        assert_includes response.body, "今日やること"
        assert_includes response.body, "実行計画を作成"
        assert_includes response.body, "採点済み"
        assert_includes response.body, admin_aicoo_revenue_executions_path(status: "planned")
        assert_includes response.body, admin_aicoo_revenue_executions_path(status: "done")
        assert_includes response.body, admin_aicoo_revenue_executions_path(status: "scored")
        assert_includes response.body, "元データ"
        assert_includes response.body, "実行予定"
        assert_includes response.body, "実行済み"
        assert_includes response.body, "予測合計価値"
        assert_includes response.body, "実績90日利益"
        assert_includes response.body, "誤差率"
        assert_includes response.body, "予測精度"
        assert_includes response.body, "結果入力"
      end

      test "shows source action candidate link and sync button after execution done" do
        action_candidate = create_action_candidate(title: "Linked action candidate", status: "in_progress")
        execution = create_execution(
          source_type: "action_candidate",
          source_id: action_candidate.id,
          title: action_candidate.title,
          status: "done",
          done_at: Time.current
        )

        get admin_aicoo_revenue_execution_url(execution)

        assert_response :success
        assert_includes response.body, action_candidate_path(action_candidate)
        assert_includes response.body, "予測者"
        assert_includes response.body, "実行計画を作成"
        assert_includes response.body, "この実行記録を完了済みにしました。元の行動候補も完了にしますか？"
        assert_includes response.body, "元の行動候補も完了にする"
      end

      test "sync button marks source action candidate done" do
        action_candidate = create_action_candidate(title: "Sync action candidate", status: "in_progress")
        execution = create_execution(
          source_type: "action_candidate",
          source_id: action_candidate.id,
          title: action_candidate.title,
          status: "done",
          done_at: Time.current
        )

        patch sync_action_candidate_done_admin_aicoo_revenue_execution_url(execution)

        assert_redirected_to admin_aicoo_revenue_execution_url(execution)
        assert_equal "done", action_candidate.reload.status
      end

      test "candidate and experiment executions do not show action candidate sync button" do
        candidate = create_candidate(title: "No sync candidate")
        experiment = AicooLabExperiment.create!(
          title: "No sync experiment",
          experiment_type: "lp",
          acquisition_channel: "seo",
          status: "running"
        )
        candidate_execution = create_execution(
          source_type: "candidate",
          source_id: candidate.id,
          title: candidate.title,
          status: "done",
          done_at: Time.current
        )
        experiment_execution = create_execution(
          source_type: "experiment",
          source_id: experiment.id,
          title: experiment.title,
          status: "done",
          done_at: Time.current
        )

        get admin_aicoo_revenue_execution_url(candidate_execution)
        assert_response :success
        assert_includes response.body, admin_aicoo_lab_candidate_path(candidate)
        assert_not_includes response.body, "元の行動候補も完了にする"

        get admin_aicoo_revenue_execution_url(experiment_execution)
        assert_response :success
        assert_includes response.body, admin_aicoo_lab_experiment_path(experiment)
        assert_not_includes response.body, "元の行動候補も完了にする"
      end

      test "marks planned execution done and skipped" do
        done_execution = create_execution(title: "Done execution")
        skipped_execution = create_execution(title: "Skipped execution")

        patch done_admin_aicoo_revenue_execution_url(done_execution)
        assert_redirected_to admin_aicoo_revenue_executions_url
        assert_equal "done", done_execution.reload.status
        assert_not_nil done_execution.done_at

        patch skipped_admin_aicoo_revenue_execution_url(skipped_execution),
              params: { aicoo_revenue_execution: { note: "Not today" } }
        assert_redirected_to admin_aicoo_revenue_executions_url
        assert_equal "skipped", skipped_execution.reload.status
        assert_equal "Not today", skipped_execution.note
        assert_not_nil skipped_execution.skipped_at
      end

      test "edits and saves revenue execution result" do
        execution = create_execution(title: "Result execution", revenue_total_value_yen: 40_000)

        get edit_admin_aicoo_revenue_execution_url(execution)
        assert_response :success
        assert_includes response.body, "実行結果入力"
        assert_includes response.body, "予測合計価値"

        patch admin_aicoo_revenue_execution_url(execution), params: {
          aicoo_revenue_execution: {
            actual_90d_profit_yen: 30_000,
            result_note: "Measured result"
          }
        }

        assert_redirected_to admin_aicoo_revenue_executions_url
        execution.reload
        assert_equal 30_000, execution.actual_90d_profit_yen
        assert_equal 0.25.to_d, execution.error_rate
        assert_equal 75.to_d, execution.calibration_score
        assert_equal "Measured result", execution.result_note
      end

      test "prefills revenue result from datahub snapshot without saving" do
        execution = create_execution(title: "Snapshot result execution", revenue_total_value_yen: 40_000)
        AicooDataSnapshot.create!(
          source_type: "revenue_execution",
          source_id: execution.id,
          payload: {
            predicted_value: 40_000,
            actual_90d_profit_yen: 28_000,
            calibration_score: 70.0
          }
        )

        assert_no_changes -> { execution.reload.actual_90d_profit_yen } do
          get edit_admin_aicoo_revenue_execution_url(execution)
        end

        assert_response :success
        assert_includes response.body, "実績データの候補値"
        assert_includes response.body, "実績90日利益候補"
        assert_includes response.body, "予測精度候補"
        assert_includes response.body, "取得日時"
        assert_includes response.body, 'value="28000"'
      end

      private

      def create_candidate(attributes = {})
        AicooLabExperimentCandidate.create!(
          {
            title: "Revenue execution candidate",
            description: "Revenue execution candidate description",
            experiment_type: "lp",
            market_category: "execution market",
            acquisition_channel: "seo",
            expected_90d_profit_yen: 50_000,
            success_probability: 0.25,
            budget_yen: 0,
            estimated_work_minutes: 60,
            rationale: "Revenue execution rationale"
          }.merge(attributes)
        )
      end

      def create_action_candidate(attributes = {})
        business = Business.create!(name: "Revenue execution business")
        ActionCandidate.create!(
          {
            business:,
            title: "Revenue execution action",
            action_type: "seo_article",
            status: "idea",
            immediate_value_yen: 80_000,
            success_probability: 0.25,
            expected_hours: 1,
            cost_yen: 0
          }.merge(attributes)
        )
      end

      def create_execution(attributes = {})
        AicooRevenueExecution.create!(
          {
            source_type: "candidate",
            source_id: AicooRevenueExecution.maximum(:source_id).to_i + 1,
            title: "Revenue execution",
            expected_90d_profit_yen: 50_000,
            success_probability: 0.25,
            revenue_total_value_yen: 12_500,
            estimated_work_minutes: 60,
            budget_yen: 0,
            revenue_score: 10,
            status: "planned"
          }.merge(attributes)
        )
      end

      def execution_params(candidate)
        {
          aicoo_revenue_execution: {
            source_type: "candidate",
            source_id: candidate.id,
            available_minutes: 180,
            available_budget_yen: 0,
            source: "all"
          }
        }
      end
    end
  end
end
