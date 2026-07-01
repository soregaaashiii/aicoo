module Aicoo
  class ResourceAwareAutoBuildSummary
    Summary = Data.define(
      :budget,
      :pending_count,
      :building_count,
      :completed_today_count,
      :failed_count,
      :codex_utilization_percent,
      :deploy_utilization_percent,
      :remaining_budget_yen,
      :scheduled_today_count,
      :learning_value_rows,
      :recent_tasks,
      :auto_deployed_new_lp_logs
    )

    LearningValueRow = Data.define(:business, :learning_value_score, :reason)

    def call
      Summary.new(
        budget:,
        pending_count: AutoBuildTask.pending.count,
        building_count: AutoBuildTask.building.count,
        completed_today_count: AutoBuildTask.completed.where(finished_at: Date.current.all_day).count,
        failed_count: AutoBuildTask.failed.count,
        codex_utilization_percent: utilization(budget.codex_waiting_count, budget.codex_waiting_limit),
        deploy_utilization_percent: utilization(budget.deploy_queue_count, budget.deploy_queue_limit),
        remaining_budget_yen: budget.remaining_budget_yen,
        scheduled_today_count: AutoBuildTask.where(created_at: Date.current.all_day).count,
        learning_value_rows:,
        recent_tasks: AutoBuildTask.includes(:business, :auto_revision_task).recent.limit(8),
        auto_deployed_new_lp_logs:
      )
    end

    private

    def budget
      @budget ||= AicooResourceBudget.current
    end

    def learning_value_rows
      Business.real_businesses
              .where(auto_build_enabled: true)
              .includes(:business_playbook, :action_results, :revenue_events, :aicoo_lab_landing_pages)
              .limit(20)
              .map { |business| row_for(business) }
              .sort_by { |row| [ -row.learning_value_score, row.business.name ] }
              .first(8)
    end

    def auto_deployed_new_lp_logs
      BusinessActivityLog.includes(:business)
                         .where(activity_type: "new_lp_auto_deploy_deploy_succeeded")
                         .recent
                         .limit(5)
    end

    def row_for(business)
      score = Aicoo::ResourceAwareAutoBuilder.new.learning_value_for_business(business)
      reason = [
        ("新規/未知カテゴリ" if business.category.blank?),
        ("Playbook少" if business.business_playbook.blank? || business.business_playbook.sample_count.to_i < 3),
        ("結果データ少" if business.action_results.count < 3),
        ("収益未検証" if business.revenue_events.revenue.count.zero?)
      ].compact.join(" / ")
      LearningValueRow.new(business:, learning_value_score: score, reason: reason.presence || "学習データを追加できます")
    end

    def utilization(current, limit)
      return 0 if limit.to_i.zero?

      ((current.to_d / limit.to_d) * 100).round
    end
  end
end
