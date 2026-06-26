module Aicoo
  class SystemModeSnapshotPresenter
    IntegrationRow = Data.define(
      :business_name,
      :business_path,
      :health_score,
      :warning_count,
      :warning,
      :last_sync_at,
      :gsc_status,
      :ga4_status,
      :serp_status,
      :explore_status
    )
    JobRow = Data.define(:target_date, :status, :started_at, :duration_seconds, :success_steps, :step_count, :retry_count, :error, :path)
    PlaybookRow = Data.define(:business_name, :business_path, :confidence_score, :sample_count, :top_action_type, :worst_action_type, :average_roi)

    def initialize(snapshot: SystemModeSnapshot.latest)
      @snapshot = snapshot
    end

    def call
      return fallback_result if snapshot.blank?

      SystemModeMonitor::Result.new(
        generated_at: Time.current,
        system_health_score: snapshot.health_score,
        system_health_status: snapshot.metadata.to_h["system_health_status"].presence || status_for_score(snapshot.health_score),
        system_health_message: snapshot_message,
        status_cards: status_cards(snapshot.metadata.to_h["status_cards"]),
        navigation: snapshot.metadata.to_h["navigation"].presence || default_navigation,
        pipeline_steps: pipeline_steps,
        integration_rows: integration_rows,
        job_rows: job_rows,
        queue_cards: status_cards(snapshot.queues_summary.to_h["cards"]),
        learning_cards: status_cards(snapshot.learning_summary.to_h["cards"]),
        playbook_rows: playbook_rows,
        executor_cards: status_cards(snapshot.executor_summary.to_h["cards"]),
        setting_cards: status_cards(snapshot.settings_summary.to_h["cards"]),
        charts: charts,
        snapshot_present: true,
        snapshot_captured_at: snapshot.captured_at,
        snapshot_age_seconds: snapshot.age_seconds,
        snapshot_warning: snapshot_warning
      )
    end

    private

    attr_reader :snapshot

    def fallback_result
      SystemModeMonitor::Result.new(
        generated_at: Time.current,
        system_health_score: 0,
        system_health_status: "attention",
        system_health_message: "Snapshot未作成です。手動RefreshまたはDaily Run後に更新されます。",
        status_cards: [
          SystemModeMonitor::StatusCard.new(
            key: "snapshot",
            label: "Snapshot",
            status: "attention",
            value: "未作成",
            detail: "Refreshしてください",
            path: "#system-health"
          )
        ],
        navigation: default_navigation,
        pipeline_steps: [],
        integration_rows: [],
        job_rows: [],
        queue_cards: [],
        learning_cards: [],
        playbook_rows: [],
        executor_cards: [],
        setting_cards: [],
        charts: [],
        snapshot_present: false,
        snapshot_captured_at: nil,
        snapshot_age_seconds: nil,
        snapshot_warning: "Snapshot未作成"
      )
    end

    def snapshot_message
      message = snapshot.metadata.to_h["system_health_message"].presence || "Snapshotから表示しています。"
      snapshot_warning ? "#{message} #{snapshot_warning}" : message
    end

    def snapshot_warning
      return "Snapshotが古くなっています。" if snapshot.stale?

      nil
    end

    def status_cards(items)
      Array(items).map do |item|
        SystemModeMonitor::StatusCard.new(
          key: item["key"],
          label: item["label"],
          status: item["status"],
          value: item["value"],
          detail: item["detail"],
          path: item["path"]
        )
      end
    end

    def pipeline_steps
      Array(snapshot.pipeline_status.to_h["steps"]).map do |item|
        SystemModeMonitor::PipelineStep.new(
          key: item["key"],
          label: item["label"],
          status: item["status"],
          count: item["count"].to_i,
          path: item["path"],
          reason: item["reason"]
        )
      end
    end

    def integration_rows
      Array(snapshot.integrations_summary.to_h["rows"]).map do |item|
        IntegrationRow.new(
          business_name: item["business_name"],
          business_path: item["business_path"],
          health_score: item["health_score"].to_d,
          warning_count: item["warning_count"].to_i,
          warning: item["warning"],
          last_sync_at: parse_time(item["last_sync_at"]),
          gsc_status: item["gsc_status"],
          ga4_status: item["ga4_status"],
          serp_status: item["serp_status"],
          explore_status: item["explore_status"]
        )
      end
    end

    def job_rows
      Array(snapshot.jobs_summary.to_h["rows"]).map do |item|
        JobRow.new(
          target_date: item["target_date"],
          status: item["status"],
          started_at: parse_time(item["started_at"]),
          duration_seconds: item["duration_seconds"],
          success_steps: item["success_steps"].to_i,
          step_count: item["step_count"].to_i,
          retry_count: item["retry_count"].to_i,
          error: item["error"],
          path: item["path"]
        )
      end
    end

    def playbook_rows
      Array(snapshot.playbook_summary.to_h["rows"]).map do |item|
        PlaybookRow.new(
          business_name: item["business_name"],
          business_path: item["business_path"],
          confidence_score: item["confidence_score"].to_d,
          sample_count: item["sample_count"].to_i,
          top_action_type: item["top_action_type"],
          worst_action_type: item["worst_action_type"],
          average_roi: item["average_roi"]&.to_d
        )
      end
    end

    def charts
      Array(snapshot.visual_analytics.to_h["charts"]).map do |item|
        SystemModeMonitor::Chart.new(
          key: item["key"],
          title: item["title"],
          unit: item["unit"],
          points: Array(item["points"]).map do |point|
            SystemModeMonitor::ChartPoint.new(
              label: point["label"],
              value: point["value"].to_d,
              status: point["status"]
            )
          end
        )
      end
    end

    def parse_time(value)
      return if value.blank?

      Time.zone.parse(value)
    end

    def status_for_score(score)
      score = score.to_d
      return "healthy" if score >= 80
      return "attention" if score >= 60
      return "warning" if score >= 40

      "critical"
    end

    def default_navigation
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
  end
end
