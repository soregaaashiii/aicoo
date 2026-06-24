module Aicoo
  class OwnerTaskInbox
    PRIORITY_ORDER = {
      "critical" => 0,
      "high" => 1,
      "medium" => 2,
      "low" => 3
    }.freeze
    TASK_TYPE_LABELS = {
      "action_candidate_approval" => "行動候補承認",
      "calibration_approval" => "評価式承認",
      "daily_run_failure" => "Daily Run失敗",
      "daily_run_partial_failed" => "Daily Run一部失敗",
      "daily_run_step_failure" => "Daily Runステップ失敗",
      "daily_run_step_recovery" => "Daily Runステップ復旧",
      "calibration_danger" => "評価式危険",
      "calibration_warning" => "評価式警告"
    }.freeze

    Result = Data.define(:tasks) do
      def counts_by_priority
        Aicoo::OwnerTaskInbox::PRIORITY_ORDER.keys.index_with { |priority| tasks.count { |task| task.priority == priority } }
      end

      def filtered(priority: nil, task_type: nil)
        tasks.select do |task|
          (priority.blank? || task.priority == priority) &&
            (task_type.blank? || task.task_type == task_type)
        end
      end
    end
    QuickAction = Data.define(:label, :method, :path, :confirm_message, :style)
    Task = Data.define(:priority, :task_type, :title, :description, :target_label, :target_path, :reason, :created_at, :quick_actions) do
      def task_type_label
        TASK_TYPE_LABELS.fetch(task_type, task_type)
      end
    end

    def call
      Result.new(tasks: sorted_tasks)
    end

    private

    def sorted_tasks
      (
        action_candidate_approval_tasks +
        calibration_approval_tasks +
        daily_run_step_recovery_tasks +
        daily_run_step_failure_tasks +
        daily_run_tasks +
        calibration_warning_tasks
      ).sort_by { |task| [ PRIORITY_ORDER.fetch(task.priority), task.created_at || Time.zone.at(0), task.title ] }
    end

    def action_candidate_approval_tasks
      ActionCandidate.includes(:business)
                     .where(status: %w[idea pending approval])
                     .where.not(status: ActionCandidate::INACTIVE_STATUSES)
                     .order(final_score: :desc, final_expected_value_yen: :desc, created_at: :desc)
                     .limit(20)
                     .map do |candidate|
        Task.new(
          priority: candidate.final_score.to_d >= 10_000.to_d ? "high" : "medium",
          task_type: "action_candidate_approval",
          title: candidate.title,
          description: "オーナー承認待ちの行動候補です。",
          target_label: candidate.business.name,
          target_path: routes.action_candidate_path(candidate),
          reason: "期待値 #{candidate.final_expected_value_yen.to_i.to_fs(:delimited)}円 / score #{candidate.final_score.to_d.round(1)}",
          created_at: candidate.created_at,
          quick_actions: action_candidate_quick_actions(candidate)
        )
      end
    end

    def calibration_approval_tasks
      pending_calibrations.map do |calibration|
        Task.new(
          priority: calibration_priority(calibration),
          task_type: "calibration_approval",
          title: "#{calibration.action_type} の評価式補正を確認",
          description: "危険または信頼度不足のため、補正係数の反映が承認待ちです。",
          target_label: calibration.action_type,
          target_path: routes.admin_aicoo_calibration_path(filter: "pending"),
          reason: calibration.warning_reason.presence || "承認待ちの補正があります。",
          created_at: calibration.approval_requested_at || calibration.updated_at,
          quick_actions: calibration_pending_quick_actions(calibration)
        )
      end
    end

    def daily_run_tasks
      AicooDailyRun.where(created_at: 7.days.ago..)
                   .where(status: %w[failed partial_failed stuck])
                   .recent
                   .limit(10)
                   .map do |run|
        Task.new(
          priority: run.status == "partial_failed" ? "high" : "critical",
          task_type: run.status == "partial_failed" ? "daily_run_partial_failed" : "daily_run_failure",
          title: "Daily Run #{run.target_date} が#{run.status}",
          description: "日次処理の結果を確認してください。",
          target_label: run.target_date.to_s,
          target_path: routes.aicoo_daily_run_path(run),
          reason: run.error_message.presence || run.calibration_error.presence || "Run Logを確認してください。",
          created_at: run.finished_at || run.started_at || run.created_at,
          quick_actions: daily_run_quick_actions(run)
        )
      end
    end

    def daily_run_step_failure_tasks
      AicooDailyRunStep.includes(:aicoo_daily_run)
                       .failed
                       .where(created_at: 7.days.ago..)
                       .recent
                       .reject(&:recovery_needed?)
                       .first(10)
                       .map do |step|
        run = step.aicoo_daily_run
        Task.new(
          priority: step.primary? ? "critical" : "high",
          task_type: "daily_run_step_failure",
          title: "Daily Run #{run.target_date} の #{step.step_name} が失敗",
          description: "日次処理の詰まり箇所を確認してください。",
          target_label: run.target_date.to_s,
          target_path: routes.aicoo_daily_run_path(run),
          reason: step.error_message.presence || "Step Breakdownを確認してください。",
          created_at: step.finished_at || step.started_at || step.created_at,
          quick_actions: daily_run_quick_actions(run)
        )
      end
    end

    def daily_run_step_recovery_tasks
      AicooDailyRunStep.includes(:aicoo_daily_run)
                       .where(status: %w[failed skipped])
                       .where(created_at: 7.days.ago..)
                       .select(&:recovery_needed?)
                       .map do |step|
        run = step.aicoo_daily_run
        Task.new(
          priority: step.step_name == "calibration" ? "high" : "medium",
          task_type: "daily_run_step_recovery",
          title: "Daily Run #{run.target_date} の #{step.step_name} を復旧",
          description: "安全な補助ステップだけ個別再実行できます。",
          target_label: run.target_date.to_s,
          target_path: routes.aicoo_daily_run_path(run, anchor: "step-breakdown"),
          reason: step.error_message.presence || "Recovery Actionを実行してください。",
          created_at: step.finished_at || step.started_at || step.created_at,
          quick_actions: daily_run_step_recovery_quick_actions(run, step)
        )
      end
    end

    def calibration_warning_tasks
      pending_action_types = pending_calibrations.map(&:action_type)
      ActionPredictionCalibration.where(warning_level: %w[danger warning])
                                 .where.not(approval_status: "pending")
                                 .reject { |calibration| pending_action_types.include?(calibration.action_type) }
                                 .map do |calibration|
        Task.new(
          priority: calibration.warning_level == "danger" ? "critical" : "high",
          task_type: calibration.warning_level == "danger" ? "calibration_danger" : "calibration_warning",
          title: "#{calibration.action_type} の補正警告",
          description: "評価関数補正に警告が出ています。",
          target_label: calibration.action_type,
          target_path: routes.admin_aicoo_calibration_path,
          reason: calibration.warning_reason.presence || "#{calibration.warning_level} 状態です。",
          created_at: calibration.factor_changed_at || calibration.last_calculated_at || calibration.updated_at,
          quick_actions: calibration_warning_quick_actions
        )
      end
    end

    def action_candidate_quick_actions(candidate)
      [
        quick_action("承認", :patch, routes.approve_action_candidate_path(candidate), style: "primary"),
        quick_action("却下", :patch, routes.reject_action_candidate_path(candidate), confirm_message: "この行動候補を却下しますか？", style: "danger"),
        quick_action("詳細を見る", :get, routes.action_candidate_path(candidate), style: "secondary")
      ]
    end

    def calibration_pending_quick_actions(calibration)
      [
        quick_action("承認", :patch, routes.approve_owner_calibration_path(calibration), confirm_message: "この補正係数を承認して反映しますか？", style: "primary"),
        quick_action("却下", :patch, routes.reject_owner_calibration_path(calibration), confirm_message: "この補正係数を却下しますか？", style: "danger"),
        quick_action("補正詳細を見る", :get, routes.admin_aicoo_calibration_path(filter: "pending"), style: "secondary")
      ]
    end

    def calibration_warning_quick_actions
      [
        quick_action("補正詳細を見る", :get, routes.admin_aicoo_calibration_path, style: "secondary")
      ]
    end

    def daily_run_quick_actions(run)
      [
        quick_action("再実行", :post, routes.aicoo_daily_runs_path(aicoo_daily_run: { target_date: run.target_date.to_s }), confirm_message: "#{run.target_date} のDaily Runを再実行しますか？", style: "primary"),
        quick_action("詳細を見る", :get, routes.aicoo_daily_run_path(run), style: "secondary")
      ]
    end

    def daily_run_step_recovery_quick_actions(run, step)
      [
        quick_action("復旧する", :post, routes.recover_aicoo_daily_run_step_path(run, step), confirm_message: "#{step.step_name} stepを再実行しますか？", style: "primary"),
        quick_action("Step Breakdownを見る", :get, routes.aicoo_daily_run_path(run, anchor: "step-breakdown"), style: "secondary")
      ]
    end

    def quick_action(label, method, path, confirm_message: nil, style: "secondary")
      QuickAction.new(label:, method:, path:, confirm_message:, style:)
    end

    def pending_calibrations
      @pending_calibrations ||= ActionPredictionCalibration.where(approval_status: "pending").order(approval_requested_at: :desc).to_a
    end

    def calibration_priority(calibration)
      return "critical" if calibration.warning_level == "danger"
      return "high" if calibration.warning_level == "warning"

      "medium"
    end

    def routes
      Rails.application.routes.url_helpers
    end
  end
end
