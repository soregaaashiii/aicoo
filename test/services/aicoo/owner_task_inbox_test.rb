require "test_helper"

module Aicoo
  class OwnerTaskInboxTest < ActiveSupport::TestCase
    setup do
      ActionResult.delete_all
      ActionExecution.delete_all
      ActionPredictionCalibration.delete_all
      AicooDailyRun.delete_all
    end

    test "returns action candidates waiting for owner approval" do
      candidate = ActionCandidate.create!(
        business: businesses(:suelog),
        title: "Owner inbox approval candidate",
        status: "idea",
        action_type: "build_lp",
        immediate_value_yen: 20_000,
        success_probability: 1,
        expected_hours: 1
      )

      tasks = OwnerTaskInbox.new.call.tasks

      task = tasks.find { |item| item.task_type == "action_candidate_approval" && item.title == candidate.title }
      assert task
      assert_equal "high", task.priority
      assert_equal Rails.application.routes.url_helpers.action_candidate_path(candidate), task.target_path
      assert_equal [ "承認", "却下", "詳細を見る" ], task.quick_actions.map(&:label)
      assert_equal Rails.application.routes.url_helpers.approve_action_candidate_path(candidate), task.quick_actions.first.path
    end

    test "returns ready action executions" do
      candidate = ActionCandidate.create!(
        business: businesses(:suelog),
        title: "Ready execution candidate",
        status: "approved",
        action_type: "seo_improvement",
        immediate_value_yen: 20_000,
        success_probability: 1,
        expected_hours: 1
      )
      execution = candidate.create_action_execution!(status: "ready", execution_type: "manual")

      task = OwnerTaskInbox.new.call.tasks.find { |item| item.task_type == "action_execution_ready" && item.title.include?(candidate.title) }

      assert task
      assert_equal "high", task.priority
      assert_equal Rails.application.routes.url_helpers.action_execution_path(execution), task.target_path
      assert_equal [ "実行開始", "詳細を見る" ], task.quick_actions.map(&:label)
    end

    test "returns completed executions without result as registration tasks" do
      candidate = ActionCandidate.create!(
        business: businesses(:suelog),
        title: "Completed execution candidate",
        status: "approved",
        action_type: "seo_improvement",
        immediate_value_yen: 20_000,
        success_probability: 1,
        expected_hours: 1
      )
      execution = candidate.create_action_execution!(
        status: "completed",
        execution_type: "manual",
        completed_at: Time.current,
        result_summary: "完了"
      )

      task = OwnerTaskInbox.new.call.tasks.find { |item| item.task_type == "action_result_registration" && item.title.include?(candidate.title) }

      assert task
      assert_equal "medium", task.priority
      assert_equal Rails.application.routes.url_helpers.action_execution_path(execution), task.target_path
      assert_equal [ "結果登録へ進む", "詳細を見る" ], task.quick_actions.map(&:label)
      assert_match "Execution completed", task.reason
    end

    test "result registration tasks become critical after 72 hours" do
      candidate = ActionCandidate.create!(
        business: businesses(:suelog),
        title: "Critical registration candidate",
        status: "approved",
        action_type: "seo_improvement",
        immediate_value_yen: 20_000,
        success_probability: 1,
        expected_hours: 1
      )
      candidate.create_action_execution!(
        status: "completed",
        execution_type: "manual",
        completed_at: 73.hours.ago,
        result_summary: "完了"
      )

      task = OwnerTaskInbox.new.call.tasks.find { |item| item.task_type == "action_result_registration" && item.title.include?(candidate.title) }

      assert task
      assert_equal "critical", task.priority
    end

    test "returns calibration pending and danger as critical" do
      ActionPredictionCalibration.create!(
        action_type: "seo_article",
        sample_count: 10,
        profit_calibration_factor: 1,
        probability_calibration_factor: 1,
        pending_profit_calibration_factor: 3,
        pending_probability_calibration_factor: 1,
        approval_status: "pending",
        warning_level: "danger",
        warning_reason: "利益補正係数が極端です",
        approval_requested_at: Time.current
      )

      task = OwnerTaskInbox.new.call.tasks.find { |item| item.task_type == "calibration_approval" }

      assert task
      assert_equal "critical", task.priority
      assert_includes task.reason, "極端"
      assert_equal [ "承認", "却下", "補正詳細を見る" ], task.quick_actions.map(&:label)
    end

    test "returns failed and stuck daily runs as critical" do
      run = AicooDailyRun.create!(
        target_date: Date.yesterday,
        status: "failed",
        source: "manual",
        error_message: "boom",
        finished_at: Time.current
      )

      task = OwnerTaskInbox.new.call.tasks.find { |item| item.task_type == "daily_run_failure" }

      assert task
      assert_equal "critical", task.priority
      assert_equal Rails.application.routes.url_helpers.aicoo_daily_run_path(run), task.target_path
      assert_includes task.reason, "boom"
      assert_equal [ "再実行", "詳細を見る" ], task.quick_actions.map(&:label)
    end

    test "returns daily run step failures as tasks" do
      run = AicooDailyRun.create!(
        target_date: Date.yesterday,
        status: "success",
        source: "manual",
        started_at: Time.current,
        finished_at: Time.current
      )
      run.aicoo_daily_run_steps.create!(
        step_name: "action_generation",
        status: "failed",
        started_at: 2.minutes.ago,
        finished_at: 1.minute.ago,
        duration_seconds: 60,
        error_message: "generation boom"
      )

      task = OwnerTaskInbox.new.call.tasks.find { |item| item.task_type == "daily_run_step_failure" }

      assert task
      assert_equal "critical", task.priority
      assert_match "action_generation", task.title
      assert_match "generation boom", task.reason
      assert_equal Rails.application.routes.url_helpers.aicoo_daily_run_path(run), task.target_path
    end

    test "returns recoverable daily run steps as recovery tasks" do
      run = AicooDailyRun.create!(
        target_date: Date.yesterday,
        status: "partial_failed",
        source: "manual",
        started_at: Time.current,
        finished_at: Time.current
      )
      step = run.aicoo_daily_run_steps.create!(
        step_name: "calibration",
        status: "failed",
        started_at: 2.minutes.ago,
        finished_at: 1.minute.ago,
        duration_seconds: 60,
        error_message: "calibration boom"
      )

      task = OwnerTaskInbox.new.call.tasks.find { |item| item.task_type == "daily_run_step_recovery" }

      assert task
      assert_equal "high", task.priority
      assert_match "calibration", task.title
      assert_equal [ "復旧する", "Step Breakdownを見る" ], task.quick_actions.map(&:label)
      assert_equal Rails.application.routes.url_helpers.recover_aicoo_daily_run_step_path(run, step), task.quick_actions.first.path
    end

    test "returns recovery attention when recoverable step is unavailable" do
      run = AicooDailyRun.create!(
        target_date: Date.yesterday,
        status: "partial_failed",
        source: "manual",
        started_at: Time.current,
        finished_at: Time.current
      )
      run.aicoo_daily_run_steps.create!(
        step_name: "calibration",
        status: "failed",
        started_at: 2.minutes.ago,
        finished_at: 1.minute.ago,
        duration_seconds: 60,
        error_message: "calibration boom",
        recovery_attempt_count: 1,
        last_recovery_at: 1.minute.ago,
        last_recovery_status: "failed"
      )

      tasks = OwnerTaskInbox.new.call.tasks
      attention = tasks.find { |item| item.task_type == "daily_run_recovery_attention" }

      assert attention
      assert_equal "high", attention.priority
      assert_match "Recovery cooldown active", attention.reason
      assert_not tasks.any? { |item| item.task_type == "daily_run_step_recovery" }
    end

    test "returns learning loop warning when accuracy is low" do
      create_evaluated_result(predicted: 10_000, actual: 0)

      task = OwnerTaskInbox.new.call.tasks.find { |item| item.task_type == "learning_loop_warning" }

      assert task
      assert_equal "high", task.priority
      assert_equal Rails.application.routes.url_helpers.owner_learning_report_path, task.target_path
      assert_equal [ "学習品質レポートを見る" ], task.quick_actions.map(&:label)
    end

    test "returns learning recommendation tasks" do
      create_evaluated_result(predicted: 10_000, actual: 1_000)

      task = OwnerTaskInbox.new.call.tasks.find { |item| item.task_type == "learning_recommendation" }

      assert task
      assert_includes %w[critical high medium low], task.priority
      assert_equal Rails.application.routes.url_helpers.owner_learning_report_path, task.quick_actions.first.path
    end

    test "returns opportunity review tasks" do
      opportunity = OpportunityDiscoveryItem.create!(
        title: "Owner discovered opportunity",
        business: businesses(:suelog),
        opportunity_score: 85
      )

      task = OwnerTaskInbox.new.call.tasks.find { |item| item.task_type == "opportunity_review" && item.title == opportunity.title }

      assert task
      assert_equal "high", task.priority
      assert_equal Rails.application.routes.url_helpers.focus_owner_opportunities_path, task.target_path
      assert_includes task.reason, "Focus Score"
      assert_equal [ "Focusで処理", "Approve", "Convert", "Opportunityを見る" ], task.quick_actions.map(&:label)
    end

    test "returns codex prompt draft needed tasks" do
      candidate = action_candidates(:nagazakicho_article)
      candidate.update!(status: "approved")
      candidate.action_execution&.destroy!
      candidate.codex_prompt_drafts.destroy_all

      task = OwnerTaskInbox.new.call.tasks.find { |item| item.task_type == "codex_prompt_draft_needed" && item.title.include?(candidate.title) }

      assert task
      assert_equal "medium", task.priority
      assert_equal Rails.application.routes.url_helpers.action_candidate_path(candidate), task.target_path
      assert_equal [ "Codex Promptを生成", "ActionCandidateを見る" ], task.quick_actions.map(&:label)
    end

    test "returns discovery source warnings" do
      create_opportunity_result(source_type: "trend", actual: 0)
      create_opportunity_result(source_type: "trend", actual: -1_000)

      task = OwnerTaskInbox.new.call.tasks.find { |item| item.task_type == "discovery_source_warning" }

      assert task
      assert_equal "high", task.priority
      assert_equal Rails.application.routes.url_helpers.owner_discovery_report_path, task.target_path
      assert_equal [ "Discovery Reportを見る" ], task.quick_actions.map(&:label)
    end

    test "returns opportunity review task for auto generated explore opportunity" do
      Aicoo::ExploreImportService.run!(
        source_type: "youtube",
        format: "csv",
        raw_text: "title,description,score\nHigh score explore signal,imported signal,92"
      )
      opportunity = OpportunityDiscoveryItem.find_by!(title: "High score explore signal")

      task = OwnerTaskInbox.new.call.tasks.find { |item| item.task_type == "opportunity_review" && item.title == opportunity.title }

      assert task
      assert_equal "high", task.priority
      assert_equal Rails.application.routes.url_helpers.focus_owner_opportunities_path, task.target_path
      assert_equal [ "Focusで処理", "Approve", "新規サービス下書き", "Opportunityを見る" ], task.quick_actions.map(&:label)
    end

    test "returns high score explore signals that are not converted yet" do
      source = ExploreDataSource.create!(name: "Manual signal source", source_type: "youtube")
      observation = ExploreObservation.create!(
        explore_data_source: source,
        title: "Unconverted explore signal",
        score: 92
      )

      task = OwnerTaskInbox.new.call.tasks.find { |item| item.task_type == "explore_signal_review" && item.title == observation.title }

      assert task
      assert_equal "high", task.priority
      assert_equal Rails.application.routes.url_helpers.admin_explore_observations_focus_path, task.target_path
      assert_equal [ "Observation Focusで処理" ], task.quick_actions.map(&:label)
    end

    test "returns explore daily routine task" do
      ExploreImportLog.delete_all

      task = OwnerTaskInbox.new.call.tasks.find { |item| item.task_type == "explore_daily_routine" }

      assert task
      assert_equal "medium", task.priority
      assert_equal Rails.application.routes.url_helpers.admin_explore_import_path, task.target_path
      assert_equal [ "Explore Importへ", "Owner Focusを見る" ], task.quick_actions.map(&:label)
    end

    test "returns non pending calibration warnings without duplicating pending action type" do
      ActionPredictionCalibration.create!(
        action_type: "seo_article",
        sample_count: 10,
        profit_calibration_factor: 1,
        probability_calibration_factor: 1,
        approval_status: "pending",
        warning_level: "danger",
        pending_profit_calibration_factor: 3,
        pending_probability_calibration_factor: 1
      )
      ActionPredictionCalibration.create!(
        action_type: "market_research",
        sample_count: 10,
        profit_calibration_factor: 1,
        probability_calibration_factor: 1,
        approval_status: "auto_applied",
        warning_level: "warning",
        warning_reason: "前回比50%以上"
      )

      tasks = OwnerTaskInbox.new.call.tasks

      assert_equal 1, tasks.count { |task| task.task_type == "calibration_approval" && task.title.include?("seo_article") }
      assert tasks.any? { |task| task.task_type == "calibration_warning" && task.title.include?("market_research") }
      assert_not tasks.any? { |task| task.task_type == "calibration_danger" && task.title.include?("seo_article") }
    end

    private

    def create_evaluated_result(predicted:, actual:)
      candidate = ActionCandidate.create!(
        business: businesses(:suelog),
        title: "Low accuracy candidate",
        status: "done",
        action_type: "seo_improvement",
        immediate_value_yen: predicted,
        success_probability: 0.8,
        expected_hours: 1
      )
      ActionResult.create!(
        action_candidate: candidate,
        business: candidate.business,
        executed_on: Date.current,
        evaluated_on: Date.current,
        evaluation_status: "evaluated",
        predicted_expected_profit_yen: predicted,
        predicted_success_probability: 0.8,
        actual_profit_yen: actual,
        actual_revenue_yen: actual
      )
    end

    def create_opportunity_result(source_type:, actual:)
      opportunity = OpportunityDiscoveryItem.create!(
        title: "#{source_type} warning opportunity #{SecureRandom.hex(4)}",
        source_type:,
        business: businesses(:suelog)
      )
      candidate = opportunity.convert_to_action_candidate!
      candidate.create_action_execution!(status: "completed", execution_type: "manual", completed_at: Time.current)
      ActionResult.create!(
        action_candidate: candidate,
        business: candidate.business,
        executed_on: Date.current,
        evaluated_on: Date.current,
        evaluation_status: "evaluated",
        predicted_expected_profit_yen: 10_000,
        predicted_success_probability: 0.8,
        actual_profit_yen: actual,
        actual_revenue_yen: actual
      )
    end
  end
end
