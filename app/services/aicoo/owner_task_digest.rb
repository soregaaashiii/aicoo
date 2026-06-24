module Aicoo
  class OwnerTaskDigest
    Result = Data.define(
      :generated_at,
      :total_open_tasks,
      :critical_count,
      :high_count,
      :medium_count,
      :low_count,
      :completed_today_count,
      :completed_yesterday_count,
      :new_since_yesterday_count,
      :top_priority_task,
      :recommended_next_action,
      :summary_message,
      :warnings,
      :daily_run_health
    )

    def initialize(owner_task_inbox: nil)
      @owner_task_inbox = owner_task_inbox
    end

    def call
      inbox = owner_task_inbox || OwnerTaskInbox.new.call
      tasks = inbox.tasks
      counts = inbox.counts_by_priority
      top_task = top_priority_task(tasks)
      daily_run_health = DailyRunHealthSummary.new.call

      Result.new(
        generated_at: Time.current,
        total_open_tasks: tasks.size,
        critical_count: counts.fetch("critical", 0),
        high_count: counts.fetch("high", 0),
        medium_count: counts.fetch("medium", 0),
        low_count: counts.fetch("low", 0),
        completed_today_count: completed_count(Date.current.all_day),
        completed_yesterday_count: completed_count(Date.yesterday.all_day),
        new_since_yesterday_count: new_since_yesterday_count(tasks),
        top_priority_task: top_task,
        recommended_next_action: recommended_next_action(top_task),
        summary_message: summary_message(tasks, counts, daily_run_health),
        warnings: warnings(tasks, counts, daily_run_health),
        daily_run_health:
      )
    end

    private

    attr_reader :owner_task_inbox

    def top_priority_task(tasks)
      tasks.max_by do |task|
        [
          -OwnerTaskInbox::PRIORITY_ORDER.fetch(task.priority, 99),
          task.created_at || Time.zone.at(0)
        ]
      end
    end

    def recommended_next_action(task)
      return unless task

      task.quick_actions.find { |action| action.label.include?("詳細") } ||
        task.quick_actions.find { |action| action.method.to_s == "get" } ||
        task.quick_actions.first
    end

    def summary_message(tasks, counts, daily_run_health)
      return "Daily Runに重大な問題があります。最優先で確認してください。" if daily_run_health.health_status == "critical"
      return "Daily Runに一部問題があります。" if daily_run_health.health_status == "warning"
      return "現在、確認が必要なタスクはありません。" if tasks.empty?
      return "Criticalタスクがあります。最優先で確認してください。" if counts.fetch("critical", 0).positive?
      return "評価関数補正の承認待ちがあります。" if tasks.any? { |task| task.task_type == "calibration_approval" }
      return "重要タスクがあります。今日中に確認してください。" if counts.fetch("high", 0).positive?

      "確認タスクがあります。空き時間で処理してください。"
    end

    def warnings(tasks, counts, daily_run_health)
      [].tap do |items|
        items.concat(daily_run_health.warnings)
        if tasks.any? { |task| task.task_type == "calibration_approval" && task.priority == "critical" }
          items << "危険度の高い評価式補正が承認待ちです。"
        end
        items << "Daily Runの失敗または停止があります。" if tasks.any? { |task| task.task_type == "daily_run_failure" }
        items << "Criticalタスクが3件以上あります。" if counts.fetch("critical", 0) >= 3
        items << "直近24時間で確認タスクが急増しています。" if new_since_yesterday_count(tasks) >= 5
      end
    end

    def completed_count(range)
      OwnerTaskCompletionLog.where(completed_at: range).count
    end

    def new_since_yesterday_count(tasks)
      since = 24.hours.ago
      tasks.count { |task| task.created_at.present? && task.created_at >= since }
    end
  end
end
