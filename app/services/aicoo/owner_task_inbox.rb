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
      "action_execution_ready" => "実行準備完了",
      "action_result_registration" => "実行結果登録",
      "learning_loop_health" => "学習ループ警告",
      "learning_loop_warning" => "学習品質警告",
      "learning_recommendation" => "学習改善提案",
      "opportunity_review" => "Opportunity確認",
      "explore_signal_review" => "Explore Signal確認",
      "explore_daily_routine" => "Explore日次確認",
      "discovery_source_warning" => "発見源警告",
      "calibration_approval" => "評価式承認",
      "daily_run_failure" => "Daily Run失敗",
      "daily_run_partial_failed" => "Daily Run一部失敗",
      "daily_run_step_failure" => "Daily Runステップ失敗",
      "daily_run_step_recovery" => "Daily Runステップ復旧",
      "daily_run_recovery_attention" => "Daily Run復旧注意",
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
        action_execution_ready_tasks +
        action_result_registration_tasks +
        learning_loop_health_tasks +
        learning_loop_warning_tasks +
        learning_recommendation_tasks +
        opportunity_review_tasks +
        explore_daily_routine_tasks +
        explore_signal_review_tasks +
        discovery_source_warning_tasks +
        calibration_approval_tasks +
        daily_run_step_recovery_tasks +
        daily_run_recovery_attention_tasks +
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

    def action_execution_ready_tasks
      ActionExecution.includes(action_candidate: :business)
                     .ready
                     .recent
                     .limit(20)
                     .map do |execution|
        candidate = execution.action_candidate
        Task.new(
          priority: candidate.final_score.to_d >= 10_000.to_d ? "high" : "medium",
          task_type: "action_execution_ready",
          title: "#{candidate.title} を実行開始",
          description: "承認済みActionCandidateの実行準備が完了しています。",
          target_label: candidate.business.name,
          target_path: routes.action_execution_path(execution),
          reason: "score #{candidate.final_score.to_d.round(1)} / 期待利益 #{candidate.expected_profit_yen.to_i.to_fs(:delimited)}円",
          created_at: execution.updated_at || execution.created_at,
          quick_actions: action_execution_quick_actions(execution)
        )
      end
    end

    def action_result_registration_tasks
      ActionExecution.includes(action_candidate: :business)
                     .completed_without_result
                     .recent
                     .limit(20)
                     .map do |execution|
        candidate = execution.action_candidate
        delay_hours = result_registration_delay_hours(execution)
        Task.new(
          priority: action_result_registration_priority(delay_hours),
          task_type: "action_result_registration",
          title: "ActionResult登録待ち: #{candidate.title}",
          description: "完了済みExecutionのActionResultが未登録です。",
          target_label: candidate.business.name,
          target_path: routes.action_execution_path(execution),
          reason: "Execution completed #{delay_hours} hours ago. 学習データ欠損防止のため、実績利益とコメントを登録してください。",
          created_at: execution.completed_at || execution.updated_at,
          quick_actions: [
            quick_action("結果登録へ進む", :get, routes.new_action_result_path(action_execution_id: execution.id), style: "primary"),
            quick_action("詳細を見る", :get, routes.action_execution_path(execution), style: "secondary")
          ]
        )
      end
    end

    def learning_loop_health_tasks
      health = LearningLoopHealthSummary.new.call
      return [] unless health.health_status.in?(%w[warning critical])

      [
        Task.new(
          priority: health.health_status == "critical" ? "critical" : "high",
          task_type: "learning_loop_health",
          title: "Learning Loop Completion Rate低下",
          description: "完了済みExecutionに対するActionResult登録率が低下しています。",
          target_label: "Learning Loop",
          target_path: routes.dashboard_path(anchor: "execution-summary"),
          reason: "#{health.health_message} missing=#{health.missing_count}件",
          created_at: Time.current,
          quick_actions: [
            quick_action("Execution Summaryを見る", :get, routes.dashboard_path(anchor: "execution-summary"), style: "secondary")
          ]
        )
      ]
    end

    def learning_loop_warning_tasks
      report = LearningLoopQualityReport.new.call
      return [] unless learning_loop_warning?(report)

      [
        Task.new(
          priority: "high",
          task_type: "learning_loop_warning",
          title: "Learning Loop Qualityを確認",
          description: "予測精度や補正効果に確認が必要です。",
          target_label: "Learning Report",
          target_path: routes.owner_learning_report_path,
          reason: learning_loop_warning_reason(report),
          created_at: report.generated_at,
          quick_actions: [
            quick_action("学習品質レポートを見る", :get, routes.owner_learning_report_path, style: "secondary")
          ]
        )
      ]
    end

    def learning_recommendation_tasks
      result = LearningReportRecommendation.new.call
      result.recommendations.reject { |recommendation| recommendation.priority == "low" }.first(3).map do |recommendation|
        Task.new(
          priority: recommendation.priority,
          task_type: "learning_recommendation",
          title: recommendation.title,
          description: "Learning Reportからの改善提案です。",
          target_label: recommendation.category,
          target_path: recommendation.target_path.presence || routes.owner_learning_report_path,
          reason: recommendation.reason,
          created_at: result.generated_at,
          quick_actions: [
            quick_action("改善提案を見る", :get, routes.owner_learning_report_path, style: "secondary")
          ]
        )
      end
    end

    def opportunity_review_tasks
      OpportunityFocusQueue.new.call.items.first(10).map do |focus_item|
        opportunity = focus_item.opportunity
        Task.new(
          priority: focus_item.priority,
          task_type: "opportunity_review",
          title: opportunity.title,
          description: "Focus Queueで優先されたOpportunityです。",
          target_label: opportunity.business&.name || opportunity.source_type,
          target_path: routes.focus_owner_opportunities_path,
          reason: "Focus Score #{focus_item.focus_score.to_i}: #{focus_item.reason}",
          created_at: opportunity.discovered_at || opportunity.created_at,
          quick_actions: [
            quick_action("Focusで処理", :get, routes.focus_owner_opportunities_path, style: "primary"),
            quick_action("Opportunityを見る", :get, routes.owner_opportunity_path(opportunity), style: "secondary")
          ]
        )
      end
    end

    def discovery_source_warning_tasks
      report = DiscoverySourcePerformanceReport.new.call
      report.weakest_sources.select { |summary| discovery_source_warning?(summary) }.first(5).map do |summary|
        Task.new(
          priority: summary.total_actual_profit.to_i.negative? ? "high" : "medium",
          task_type: "discovery_source_warning",
          title: "#{summary.source_type} の発見源成績を確認",
          description: "Discovery Source Performanceで成功率または実績利益に警告があります。",
          target_label: summary.source_type,
          target_path: routes.owner_discovery_report_path,
          reason: "成功率 #{(summary.overall_success_rate * 100).round(1)}% / 実績利益 #{summary.total_actual_profit.to_i.to_fs(:delimited)}円",
          created_at: report.generated_at,
          quick_actions: [
            quick_action("Discovery Reportを見る", :get, routes.owner_discovery_report_path, style: "secondary")
          ]
        )
      end
    end

    def explore_signal_review_tasks
      Aicoo::ExploreObservationFocusQueue.new.call.observations.select { |observation| observation.score.to_d >= 80.to_d }.first(10).map do |observation|
        Task.new(
          priority: observation.score.to_d >= 90.to_d ? "high" : "medium",
          task_type: "explore_signal_review",
          title: observation.title,
          description: "高スコアのExplore Signalです。Opportunity化を確認してください。",
          target_label: observation.explore_data_source.source_type,
          target_path: routes.admin_explore_observations_focus_path,
          reason: "score #{observation.score.to_i} / #{observation.observation_type}",
          created_at: observation.observed_at || observation.created_at,
          quick_actions: [
            quick_action("Observation Focusで処理", :get, routes.admin_explore_observations_focus_path, style: "secondary")
          ]
        )
      end
    end

    def explore_daily_routine_tasks
      routine = ExploreDailyRoutine.new.call
      return [] if routine.routine_status == "clear"

      [
        Task.new(
          priority: explore_daily_routine_priority(routine),
          task_type: "explore_daily_routine",
          title: "Explore Daily Routine: #{routine.recommended_next_step.label}",
          description: "Exploreの今日やる作業を確認してください。",
          target_label: routine.routine_status,
          target_path: routine.recommended_next_step.path,
          reason: routine.recommended_next_step.reason,
          created_at: routine.generated_at,
          quick_actions: [
            quick_action(routine.recommended_next_step.label, :get, routine.recommended_next_step.path, style: "primary"),
            quick_action("Owner Focusを見る", :get, routes.owner_focus_path, style: "secondary")
          ]
        )
      ]
    end

    def explore_daily_routine_priority(routine)
      return "high" if routine.routine_status == "overloaded"
      return "high" if routine.high_score_observation_count.positive?
      return "high" if routine.high_priority_opportunity_count.positive?
      return "medium" if routine.import_needed

      "medium"
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
                       .select(&:recovery_available?)
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

    def daily_run_recovery_attention_tasks
      AicooDailyRunStep.includes(:aicoo_daily_run)
                       .where(status: %w[failed skipped])
                       .where(created_at: 7.days.ago..)
                       .select { |step| step.recovery_needed? && !step.recovery_available? }
                       .map do |step|
        run = step.aicoo_daily_run
        Task.new(
          priority: "high",
          task_type: "daily_run_recovery_attention",
          title: "Daily Run #{run.target_date} の #{step.step_name} は復旧待機中",
          description: "Recovery Safety Guardにより今は再実行できません。",
          target_label: run.target_date.to_s,
          target_path: routes.aicoo_daily_run_path(run, anchor: "step-breakdown"),
          reason: step.recovery_unavailable_reason.presence || "Recovery unavailable",
          created_at: step.finished_at || step.started_at || step.created_at,
          quick_actions: [
            quick_action("Step Breakdownを見る", :get, routes.aicoo_daily_run_path(run, anchor: "step-breakdown"), style: "secondary")
          ]
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

    def action_execution_quick_actions(execution)
      [
        quick_action("実行開始", :patch, routes.start_action_execution_path(execution), style: "primary"),
        quick_action("詳細を見る", :get, routes.action_execution_path(execution), style: "secondary")
      ]
    end

    def result_registration_delay_hours(execution)
      return 0 unless execution.completed_at

      ((Time.current - execution.completed_at) / 1.hour).round(1)
    end

    def action_result_registration_priority(delay_hours)
      return "critical" if delay_hours >= 72
      return "high" if delay_hours >= 24

      "medium"
    end

    def learning_loop_warning?(report)
      report.learning_trend == "declining" ||
        (report.prediction_accuracy_score.present? && report.prediction_accuracy_score < 50) ||
        (report.calibration_effectiveness_score.is_a?(Numeric) && report.calibration_effectiveness_score < 40)
    end

    def learning_loop_warning_reason(report)
      return "Learning Trend declining" if report.learning_trend == "declining"
      return "Accuracy Score #{report.prediction_accuracy_score}" if report.prediction_accuracy_score.to_i < 50

      "Calibration Effectiveness #{report.calibration_effectiveness_score}"
    end

    def discovery_source_warning?(summary)
      summary.results_count >= DiscoverySourcePerformanceReport::MIN_SAMPLE_SIZE &&
        (summary.overall_success_rate.to_d < 0.4.to_d || summary.total_actual_profit.to_i.negative?)
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
