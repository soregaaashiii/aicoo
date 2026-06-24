module Aicoo
  class OwnerFocusHome
    TARGET_TASK_TYPES = %w[
      action_result_registration
      action_execution_ready
      calibration_approval
      opportunity_review
      daily_run_failure
      daily_run_step_recovery
      learning_recommendation
    ].freeze

    Result = Data.define(
      :top_task,
      :focus_tasks,
      :total_count,
      :critical_count,
      :high_count,
      :generated_at,
      :summary_message
    )

    def initialize(owner_task_inbox: nil)
      @owner_task_inbox = owner_task_inbox
    end

    def call
      Result.new(
        top_task: focus_tasks.first,
        focus_tasks:,
        total_count: focus_tasks.size,
        critical_count: focus_tasks.count { |task| task.priority == "critical" },
        high_count: focus_tasks.count { |task| task.priority == "high" },
        generated_at: Time.current,
        summary_message: summary_message
      )
    end

    private

    attr_reader :owner_task_inbox

    def focus_tasks
      @focus_tasks ||= inbox.tasks
                            .select { |task| TARGET_TASK_TYPES.include?(task.task_type) }
                            .sort_by { |task| [ task_rank(task), task.created_at || Time.zone.at(0), task.title ] }
    end

    def inbox
      @inbox ||= owner_task_inbox || OwnerTaskInbox.new.call
    end

    def task_rank(task)
      return 0 if task.task_type == "daily_run_failure"
      return 1 if task.task_type == "action_result_registration" && task.priority == "critical"
      return 2 if task.task_type == "calibration_approval" && task.priority == "critical"
      return 3 if task.task_type == "action_execution_ready"
      return 4 if task.task_type == "opportunity_review" && task.priority == "high"
      return 5 if task.task_type == "learning_recommendation"
      return 6 if task.task_type == "daily_run_step_recovery"

      10 + OwnerTaskInbox::PRIORITY_ORDER.fetch(task.priority, 99)
    end

    def summary_message
      return "今すぐ処理すべきタスクはありません。" if focus_tasks.empty?
      return "Daily Runに異常があります。最優先で確認してください。" if focus_tasks.first.task_type == "daily_run_failure"
      return "結果未登録が滞留しています。学習ループを止めないために登録してください。" if focus_tasks.first.task_type == "action_result_registration"

      "次に押すべき1件を表示しています。"
    end
  end
end
