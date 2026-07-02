require "test_helper"

module Admin
  module AicooExecutor
    class TasksControllerTest < ActionDispatch::IntegrationTest
      test "shows executor dashboard counts" do
        AicooExecutorTask.create!(
          title: "Approved executor task",
          source_type: "lab_candidate",
          source_id: 1,
          execution_type: "lp_creation",
          status: "approved"
        )
        AicooExecutorTask.create!(
          title: "Pending executor task",
          source_type: "lab_candidate",
          source_id: 2,
          execution_type: "seo_content",
          status: "approval_pending"
        )
        AicooExecutorTask.create!(
          title: "Done executor task",
          source_type: "lab_candidate",
          source_id: 3,
          execution_type: "custom",
          status: "done"
        )
        AicooExecutorTask.create!(
          title: "Data preparation executor task",
          source_type: "action_candidate",
          source_id: 4,
          execution_type: "data_preparation",
          status: "approval_pending"
        )

        get admin_aicoo_executor_url

        assert_response :success
        assert_includes response.body, "実行指示"
        assert_includes response.body, "この画面でやること"
        assert_includes response.body, "Codexへ貼れる実行指示"
        assert_includes response.body, "実行待ち"
        assert_includes response.body, "承認待ち"
        assert_includes response.body, "完了"
        assert_includes response.body, "Approved executor task"
        assert_includes response.body, "Pending executor task"
        assert_includes response.body, "Done executor task"
        assert_includes response.body, "データ整備タスク"
        assert_includes response.body, "Data preparation executor task"
        assert_includes response.body, "実行タイプ"
        assert_includes response.body, "作成日時"
      end

      test "filters data preparation executor tasks" do
        AicooExecutorTask.create!(
          title: "Only data preparation",
          source_type: "action_candidate",
          source_id: 1,
          execution_type: "data_preparation",
          status: "approval_pending"
        )
        AicooExecutorTask.create!(
          title: "Other task",
          source_type: "lab_candidate",
          source_id: 2,
          execution_type: "custom",
          status: "approval_pending"
        )

        get admin_aicoo_executor_url(execution_type: "data_preparation")

        assert_response :success
        assert_includes response.body, "Only data preparation"
        assert_not_includes response.body, "Other task"
      end

      test "shows codex waiting auto revision tasks filter" do
        task = AutoRevisionTask.from_action_candidate(action_candidates(:nagazakicho_article))
        task.approve!

        get admin_aicoo_executor_url(codex_filter: "waiting")

        assert_response :success
        assert_includes response.body, "Codex送信待ち"
        assert_includes response.body, task.title
        assert_includes response.body, businesses(:suelog).name
        assert_includes response.body, "プロンプト確認"
        assert_includes response.body, "手動送信済みにする"
      end

      test "creates executor task from revenue execution" do
        candidate = create_candidate(title: "Executor LP candidate")
        execution = create_revenue_execution(source_id: candidate.id, title: candidate.title)

        assert_difference("AicooExecutorTask.count") do
          post admin_aicoo_executor_tasks_url, params: {
            aicoo_executor_task: {
              aicoo_revenue_execution_id: execution.id
            }
          }
        end

        task = AicooExecutorTask.last
        assert_redirected_to admin_aicoo_executor_task_url(task)
        assert_equal "approval_pending", task.status
        assert_equal "lab_candidate", task.source_type
        assert_equal candidate.id, task.source_id
        assert_includes task.execution_prompt, "LPを作成"
        assert_includes task.execution_prompt, "db:drop / db:reset / drop database は絶対禁止"
      end

      test "shows executor task details and prompt" do
        task = AicooExecutorTask.create!(
          title: "Prompt executor task",
          source_type: "lab_candidate",
          source_id: 1,
          execution_type: "custom",
          execution_prompt: "実行プロンプト本文",
          estimated_minutes: 30,
          status: "approval_pending"
        )

        get admin_aicoo_executor_task_url(task)

        assert_response :success
        assert_includes response.body, "Prompt executor task"
        assert_includes response.body, "Codex実行指示"
        assert_includes response.body, "コピー"
        assert_includes response.body, "executor_prompt"
        assert_includes response.body, "この内容をCodexに貼って実行してください"
        assert_includes response.body, "先に承認してください"
        assert_includes response.body, "実行プロンプト本文"
        assert_includes response.body, "承認"
        assert_includes response.body, "却下"
      end

      test "approves and completes executor task" do
        task = AicooExecutorTask.create!(
          title: "Lifecycle executor task",
          source_type: "lab_candidate",
          source_id: 1,
          execution_type: "custom",
          status: "approval_pending"
        )

        patch approve_admin_aicoo_executor_task_url(task)

        assert_redirected_to admin_aicoo_executor_task_url(task)
        assert_equal "approved", task.reload.status
        assert_not_nil task.approved_at

        patch done_admin_aicoo_executor_task_url(task)

        assert_redirected_to admin_aicoo_executor_task_url(task)
        assert_equal "done", task.reload.status
        assert_not_nil task.done_at
      end

      private

      def create_candidate(attributes = {})
        AicooLabExperimentCandidate.create!(
          {
            title: "Executor candidate",
            description: "Executor candidate description",
            experiment_type: "lp",
            market_category: "executor market",
            acquisition_channel: "seo",
            expected_90d_profit_yen: 50_000,
            success_probability: 0.25,
            budget_yen: 0,
            estimated_work_minutes: 60,
            rationale: "Executor rationale"
          }.merge(attributes)
        )
      end

      def create_revenue_execution(attributes = {})
        AicooRevenueExecution.create!(
          {
            source_type: "candidate",
            source_id: 1,
            title: "Executor revenue execution",
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
    end
  end
end
