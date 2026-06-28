module Aicoo
  class SystemModeMonitor
    StatusCard = Data.define(:key, :label, :status, :value, :detail, :path)
    PipelineStep = Data.define(:key, :label, :status, :count, :path, :reason)
    Chart = Data.define(:key, :title, :unit, :points)
    ChartPoint = Data.define(:label, :value, :status)
    Result = Data.define(
      :generated_at,
      :system_health_score,
      :system_health_status,
      :system_health_message,
      :status_cards,
      :navigation,
      :pipeline_steps,
      :integration_rows,
      :job_rows,
      :queue_cards,
      :learning_cards,
      :playbook_rows,
      :executor_cards,
      :setting_cards,
      :charts,
      :snapshot_present,
      :snapshot_captured_at,
      :snapshot_age_seconds,
      :snapshot_warning
    )

    HEALTH_STATUS_SCORES = {
      "healthy" => 100,
      "attention" => 78,
      "warning" => 55,
      "critical" => 25
    }.freeze

    def call
      Result.new(
        generated_at: Time.current,
        system_health_score:,
        system_health_status: status_for_score(system_health_score),
        system_health_message:,
        status_cards:,
        navigation:,
        pipeline_steps:,
        integration_rows: business_integration_health.business_healths,
        job_rows: AicooDailyRun.includes(:aicoo_daily_run_steps).recent.limit(8),
        queue_cards:,
        learning_cards:,
        playbook_rows: BusinessPlaybook.includes(:business).order(confidence_score: :desc).limit(8),
        executor_cards:,
        setting_cards:,
        charts:,
        snapshot_present: false,
        snapshot_captured_at: Time.current,
        snapshot_age_seconds: 0,
        snapshot_warning: nil
      )
    end

    private

    def system_health_score
      @system_health_score ||= begin
        scores = [
          business_integration_health.average_health_score,
          HEALTH_STATUS_SCORES.fetch(daily_run_health.health_status, 50),
          learning_loop_quality_report.prediction_accuracy_score || 50,
          queue_health_score,
          executor_health_score
        ].compact.map(&:to_d)
        return 0.to_d if scores.empty?

        (scores.sum / scores.size).round(1)
      end
    end

    def system_health_message
      case status_for_score(system_health_score)
      when "healthy"
        "AICOOは通常運用です。"
      when "attention"
        "一部に確認ポイントがあります。"
      when "warning"
        "AICOOの一部処理に遅れ・警告があります。"
      else
        "AICOOに重大な運用異常があります。"
      end
    end

    def status_cards
      [
        StatusCard.new(
          key: "health",
          label: "System Health",
          status: status_for_score(system_health_score),
          value: system_health_score,
          detail: system_health_message,
          path: "#system-health"
        ),
        StatusCard.new(
          key: "daily_run",
          label: "Daily Run",
          status: daily_run_health.health_status,
          value: daily_run_health.latest_status || "未実行",
          detail: daily_run_health.health_message,
          path: "/aicoo_daily_runs"
        ),
        StatusCard.new(
          key: "integrations",
          label: "Integrations",
          status: business_integration_health.critical_businesses.any? ? "critical" : integrations_status,
          value: "#{business_integration_health.critical_businesses.size} critical",
          detail: "Business連携 #{business_integration_health.business_healths.size}件を監視",
          path: "#system-integrations"
        ),
        StatusCard.new(
          key: "queues",
          label: "Queues",
          status: queue_status,
          value: "#{OwnerExecutionQueueItem.today.pending.count} pending",
          detail: "Owner / Opportunity / Codex queue",
          path: "#system-queues"
        ),
        StatusCard.new(
          key: "learning",
          label: "Learning",
          status: learning_loop_quality_report.learning_trend == "declining" ? "warning" : "healthy",
          value: learning_loop_quality_report.learning_trend,
          detail: "Accuracy #{learning_loop_quality_report.prediction_accuracy_score || 'N/A'}",
          path: "#system-learning"
        ),
        StatusCard.new(
          key: "executor",
          label: "Executor",
          status: executor_status,
          value: "#{auto_revision_task_summary.running_count} running",
          detail: "#{auto_revision_task_summary.ready_for_codex_count} ready / #{auto_revision_task_summary.failed_count} failed",
          path: "#system-executor"
        )
      ]
    end

    def navigation
      [
        [ "Health", "#system-health" ],
        [ "Integrations", "#system-integrations" ],
        [ "Pipelines", "#system-pipeline" ],
        [ "Jobs", "#system-jobs" ],
        [ "Queues", "#system-queues" ],
        [ "Learning", "#system-learning" ],
        [ "Playbook", "#system-playbook" ],
        [ "Executor", "#system-executor" ],
        [ "Settings", "#system-settings" ]
      ]
    end

    def pipeline_steps
      [
        pipeline_step("data", "Data", AnalyticsFetchRun.where(created_at: 7.days.ago..).count, "/admin/analytics_imports"),
        pipeline_step("explore", "Explore", ExploreObservation.where(created_at: 7.days.ago..).count, "/admin/explore"),
        pipeline_step("opportunity", "Opportunity", OpportunityDiscoveryItem.where(created_at: 7.days.ago..).count, "/owner/opportunities"),
        pipeline_step("action_candidate", "ActionCandidate", ActionCandidate.where(created_at: 7.days.ago..).count, "/action_candidates"),
        pipeline_step("codex_prompt", "Codex Prompt", CodexPromptDraft.where(created_at: 7.days.ago..).count, "/owner/codex_prompt_drafts"),
        pipeline_step("execution_queue", "Execution Queue", OwnerExecutionQueueItem.where(created_at: 7.days.ago..).count, "/owner/tasks"),
        pipeline_step("decision_log", "Decision Log", OwnerDecisionLog.where(decided_at: 7.days.ago..).count, "/owner/learning_report"),
        pipeline_step("playbook", "Playbook", BusinessPlaybook.where.not(last_calculated_at: nil).count, "/owner/learning_report"),
        pipeline_step("strategic_learning", "Strategic Learning", strategic_learning_report.guardrail_warning_30_days_count, "/owner/learning_report", inverse: true)
      ]
    end

    def pipeline_step(key, label, count, path, inverse: false)
      status = if inverse
        count.positive? ? "warning" : "healthy"
      elsif count.zero?
        "attention"
      else
        "healthy"
      end
      reason = inverse ? "Guardrail warning #{count}件" : "直近7日 #{count}件"
      PipelineStep.new(key:, label:, status:, count:, path:, reason:)
    end

    def queue_cards
      [
        StatusCard.new(key: "opportunity", label: "Opportunity Queue", status: queue_status_for(OpportunityDiscoveryItem.pending_review.count), value: OpportunityDiscoveryItem.pending_review.count, detail: "review待ち", path: "/owner/opportunities/focus"),
        StatusCard.new(key: "execution", label: "Execution Queue", status: queue_status_for(OwnerExecutionQueueItem.today.pending.count), value: OwnerExecutionQueueItem.today.pending.count, detail: "今日のpending", path: "/owner/tasks"),
        StatusCard.new(key: "retry", label: "Retry Queue", status: AicooDailyRun.retryable.exists? ? "warning" : "healthy", value: AicooDailyRun.retryable.count, detail: "retry可能Run", path: "/aicoo_daily_runs"),
        StatusCard.new(key: "completed", label: "Completed Today", status: "healthy", value: OwnerExecutionQueueItem.today.completed.count, detail: "今日処理済み", path: "/owner/tasks")
      ]
    end

    def learning_cards
      [
        StatusCard.new(key: "decision", label: "Decision Log", status: OwnerDecisionLog.where(decided_at: 7.days.ago..).exists? ? "healthy" : "attention", value: OwnerDecisionLog.where(decided_at: Date.current.all_day).count, detail: "今日の意思決定", path: "/owner/learning_report"),
        StatusCard.new(key: "strategic", label: "Strategic Learning", status: strategic_learning_report.guardrail_warning_30_days_count.positive? ? "warning" : "healthy", value: "#{strategic_learning_report.guardrail_warning_30_days_count} warnings", detail: "Guardrail", path: "/owner/learning_report"),
        StatusCard.new(key: "evidence", label: "Evidence", status: evidence_summary.insufficient_evidence_count.positive? ? "attention" : "healthy", value: evidence_summary.average_evidence_score, detail: "平均Evidence", path: "/owner/learning_report"),
        StatusCard.new(key: "practicality", label: "Practicality", status: practicality_summary.low_practicality_count.positive? ? "attention" : "healthy", value: practicality_summary.average_practicality_score, detail: "平均Practicality", path: "/owner/learning_report")
      ]
    end

    def executor_cards
      [
        StatusCard.new(key: "approved", label: "Approved", status: "healthy", value: auto_revision_task_summary.approved_count, detail: "承認済み", path: "/auto_revision_tasks"),
        StatusCard.new(key: "ready", label: "Ready", status: queue_status_for(auto_revision_task_summary.ready_for_codex_count), value: auto_revision_task_summary.ready_for_codex_count, detail: "Codex投入待ち", path: "/auto_revision_tasks/codex_queue"),
        StatusCard.new(key: "copied", label: "Copied", status: "healthy", value: auto_revision_task_summary.exported_codex_prompt_count, detail: "export済み", path: "/auto_revision_tasks/codex_queue"),
        StatusCard.new(key: "executed", label: "Executed", status: auto_revision_task_summary.failed_count.positive? ? "warning" : "healthy", value: auto_revision_task_summary.succeeded_count, detail: "#{auto_revision_task_summary.failed_count} failed", path: "/auto_revision_tasks")
      ]
    end

    def setting_cards
      [
        StatusCard.new(key: "strategic", label: "Strategic Weight", status: "healthy", value: "設定", detail: "経営思想Weight", path: "/aicoo_setting"),
        StatusCard.new(key: "guardrail", label: "Guardrail", status: strategic_learning_report.guardrail_warning_30_days_count.positive? ? "warning" : "healthy", value: strategic_learning_report.guardrail_warning_30_days_count, detail: "warning", path: "/aicoo_setting"),
        StatusCard.new(key: "queue", label: "Queue", status: AicooAutoRevisionSetting.current.enabled? ? "healthy" : "attention", value: AicooAutoRevisionSetting.current.enabled? ? "ON" : "OFF", detail: "Auto Revision", path: "/admin/aicoo_auto_revision_settings"),
        StatusCard.new(key: "retry", label: "Retry", status: AicooDailyRunSetting.current.retry_until_success? ? "healthy" : "attention", value: AicooDailyRunSetting.current.retry_until_success? ? "ON" : "OFF", detail: "Daily Run", path: "/admin/aicoo_daily_run_settings")
      ]
    end

    def charts
      [
        daily_chart("prediction_accuracy", "Prediction Accuracy", "%") { |date| daily_accuracy_value(date) },
        daily_chart("decision_log", "Decision Log", "件") { |date| OwnerDecisionLog.where(decided_at: date.all_day).count },
        daily_chart("revenue", "Revenue", "円") { |date| RevenueEvent.revenue.where(occurred_on: date).sum(:amount) },
        business_health_chart,
        daily_chart("evidence", "Evidence Score", "") { |date| average_evidence_for(date) },
        daily_chart("practicality", "Practicality", "") { |date| average_practicality_for(date) },
        playbook_confidence_chart,
        daily_chart("opportunities", "Opportunity生成数", "件") { |date| OpportunityDiscoveryItem.where(created_at: date.all_day).count },
        daily_chart("action_candidates", "ActionCandidate生成数", "件") { |date| ActionCandidate.where(created_at: date.all_day).count },
        queue_chart,
        daily_chart("daily_run_duration", "Daily Run時間", "秒") { |date| daily_run_duration_for(date) },
        daily_chart("errors", "Error数", "件") { |date| AicooDailyRun.where(created_at: date.all_day, status: %w[failed partial_failed stuck]).count }
      ]
    end

    def daily_chart(key, title, unit)
      Chart.new(
        key:,
        title:,
        unit:,
        points: chart_dates.map { |date| ChartPoint.new(label: date.strftime("%m/%d"), value: yield(date).to_d.round(1), status: "healthy") }
      )
    end

    def business_health_chart
      Chart.new(
        key: "health_score",
        title: "Health Trend",
        unit: "",
        points: business_integration_health.business_healths.map do |row|
          ChartPoint.new(label: row.business.name, value: row.health_score.to_d.round(1), status: status_for_score(row.health_score))
        end
      )
    end

    def playbook_confidence_chart
      Chart.new(
        key: "playbook_confidence",
        title: "Playbook Confidence",
        unit: "",
        points: Business.real_businesses.includes(:business_playbook).order(:name).map do |business|
          score = business.business_playbook&.confidence_score.to_d
          ChartPoint.new(label: business.name, value: score.round(1), status: status_for_score(score))
        end
      )
    end

    def queue_chart
      Chart.new(
        key: "execution_queue",
        title: "Execution Queue",
        unit: "件",
        points: %w[pending completed skipped].map do |status|
          ChartPoint.new(label: status, value: OwnerExecutionQueueItem.today.where(status:).count, status: status == "pending" ? queue_status : "healthy")
        end
      )
    end

    def chart_dates
      @chart_dates ||= (6.days.ago.to_date..Date.current).to_a
    end

    def daily_accuracy_value(date)
      results = ActionResult.where(created_at: date.all_day)
      return 0 if results.empty?

      100
    end

    def average_practicality_for(date)
      average(ActionCandidate.where(created_at: date.all_day).where.not(practicality_score: nil).pluck(:practicality_score))
    end

    def average_evidence_for(date)
      scores = ActionCandidate.where(created_at: date.all_day).map { |candidate| candidate.metadata.to_h.dig("evidence", "score").to_d }.select(&:positive?)
      average(scores)
    end

    def daily_run_duration_for(date)
      runs = AicooDailyRun.where(created_at: date.all_day).where.not(started_at: nil, finished_at: nil)
      durations = runs.map { |run| run.finished_at && run.started_at ? run.finished_at - run.started_at : nil }.compact
      average(durations)
    end

    def average(values)
      values = values.compact.map(&:to_d)
      return 0.to_d if values.empty?

      (values.sum / values.size).round(1)
    end

    def queue_status
      pending = OwnerExecutionQueueItem.today.pending.count
      return "healthy" if pending < 5
      return "attention" if pending < 10

      "warning"
    end

    def integrations_status
      business_integration_health.warning_businesses.any? ? "attention" : "healthy"
    end

    def executor_status
      return "warning" if auto_revision_task_summary.failed_count.positive? || auto_revision_task_summary.stale_codex_task_count.positive?
      return "attention" if auto_revision_task_summary.ready_for_codex_count.positive?

      "healthy"
    end

    def queue_health_score
      { "healthy" => 100, "attention" => 75, "warning" => 50, "critical" => 20 }.fetch(queue_status, 50)
    end

    def executor_health_score
      { "healthy" => 100, "attention" => 75, "warning" => 50, "critical" => 20 }.fetch(executor_status, 50)
    end

    def queue_status_for(count)
      return "healthy" if count.to_i.zero?
      return "attention" if count.to_i < 5

      "warning"
    end

    def status_for_score(score)
      score = score.to_d
      return "healthy" if score >= 80
      return "attention" if score >= 60
      return "warning" if score >= 40

      "critical"
    end

    def business_integration_health
      @business_integration_health ||= BusinessIntegrationHealth.new.call
    end

    def daily_run_health
      @daily_run_health ||= DailyRunHealthSummary.new.call
    end

    def learning_loop_quality_report
      @learning_loop_quality_report ||= LearningLoopQualityReport.new.call
    end

    def strategic_learning_report
      @strategic_learning_report ||= StrategicLearningReport.new.call
    end

    def evidence_summary
      @evidence_summary ||= EvidenceSummary.new.call
    end

    def practicality_summary
      @practicality_summary ||= PracticalitySummary.new.call
    end

    def auto_revision_task_summary
      @auto_revision_task_summary ||= AutoRevisionTaskSummary.new.call
    end
  end
end
