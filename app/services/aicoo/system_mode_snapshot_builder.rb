module Aicoo
  class SystemModeSnapshotBuilder
    def call(captured_at: Time.current)
      monitor = SystemModeMonitor.new.call
      SystemModeSnapshot.create!(
        captured_at:,
        health_score: monitor.system_health_score,
        warning_count: monitor.status_cards.count { |card| %w[attention warning].include?(card.status) },
        critical_count: monitor.status_cards.count { |card| card.status == "critical" },
        pipeline_status: {
          "steps" => monitor.pipeline_steps.map { |step| pipeline_payload(step) }
        },
        integrations_summary: {
          "rows" => monitor.integration_rows.map { |row| integration_payload(row) }
        },
        jobs_summary: {
          "rows" => monitor.job_rows.map { |run| job_payload(run) }
        },
        queues_summary: {
          "cards" => monitor.queue_cards.map { |card| status_card_payload(card) }
        },
        learning_summary: {
          "cards" => monitor.learning_cards.map { |card| status_card_payload(card) }
        },
        playbook_summary: {
          "rows" => monitor.playbook_rows.map { |playbook| playbook_payload(playbook) }
        },
        executor_summary: {
          "cards" => monitor.executor_cards.map { |card| status_card_payload(card) }
        },
        settings_summary: {
          "cards" => monitor.setting_cards.map { |card| status_card_payload(card) }
        },
        visual_analytics: {
          "charts" => monitor.charts.map { |chart| chart_payload(chart) }
        },
        metadata: {
          "system_health_status" => monitor.system_health_status,
          "system_health_message" => monitor.system_health_message,
          "status_cards" => monitor.status_cards.map { |card| status_card_payload(card) },
          "navigation" => monitor.navigation
        }
      )
    end

    private

    def status_card_payload(card)
      {
        "key" => card.key,
        "label" => card.label,
        "status" => card.status,
        "value" => card.value.to_s,
        "detail" => card.detail.to_s,
        "path" => card.path.to_s
      }
    end

    def pipeline_payload(step)
      {
        "key" => step.key,
        "label" => step.label,
        "status" => step.status,
        "count" => step.count.to_i,
        "path" => step.path,
        "reason" => step.reason
      }
    end

    def integration_payload(row)
      {
        "business_name" => row.business.name,
        "business_path" => Rails.application.routes.url_helpers.business_path(row.business),
        "health_score" => row.health_score.to_s,
        "warning_count" => row.warning_count,
        "warning" => row.warnings.first,
        "last_sync_at" => row.last_sync_at&.iso8601,
        "gsc_status" => row.gsc.status,
        "ga4_status" => row.ga4.status,
        "serp_status" => row.serp.status,
        "explore_status" => row.explore.status
      }
    end

    def job_payload(run)
      duration = run.started_at && run.finished_at ? (run.finished_at - run.started_at).round(1) : nil
      {
        "id" => run.id,
        "target_date" => run.target_date.to_s,
        "status" => run.status,
        "started_at" => run.started_at&.iso8601,
        "duration_seconds" => duration,
        "success_steps" => run.aicoo_daily_run_steps.successful.count,
        "step_count" => run.aicoo_daily_run_steps.count,
        "retry_count" => run.retry_count,
        "error" => [ run.error_message, run.calibration_error ].compact_blank.first,
        "path" => Rails.application.routes.url_helpers.aicoo_daily_run_path(run)
      }
    end

    def playbook_payload(playbook)
      {
        "business_name" => playbook.business.name,
        "business_path" => Rails.application.routes.url_helpers.business_path(playbook.business),
        "confidence_score" => playbook.confidence_score.to_s,
        "sample_count" => playbook.sample_count,
        "top_action_type" => playbook.top_action_type,
        "worst_action_type" => playbook.worst_action_type,
        "average_roi" => playbook.average_roi&.to_s
      }
    end

    def chart_payload(chart)
      {
        "key" => chart.key,
        "title" => chart.title,
        "unit" => chart.unit,
        "points" => chart.points.map do |point|
          {
            "label" => point.label,
            "value" => point.value.to_s,
            "status" => point.status
          }
        end
      }
    end
  end
end
