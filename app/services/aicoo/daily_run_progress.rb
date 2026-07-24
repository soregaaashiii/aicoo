module Aicoo
  class DailyRunProgress
    DEFAULT_STEP_DURATION_SECONDS = 60.0
    MAX_CURRENT_STEP_FRACTION = 0.95
    HISTORY_SAMPLE_LIMIT = 2_000

    STEP_DEFINITIONS = [
      [ "analytics_fetch", "Analytics" ],
      [ "datahub_collect", "Data Hub" ],
      [ "business_metrics_import", "Business Metrics Import" ],
      [ "activity_log_evaluation_queue_build", "Activity Evaluation" ],
      [ "suelog_database_health_check", "Suelog Health" ],
      [ "suelog_candidate_generation", "Suelog Candidates" ],
      [ "article_opportunity_analysis", "Article Opportunity" ],
      [ "landing_page_opportunity_analysis", "LP Opportunity" ],
      [ "source_app_diff_detection", "Source App Diff" ],
      [ "proxy_weight_adjustment", "Proxy Weight" ],
      [ "action_generation", "Action Generation" ],
      [ "insight_generation", "Insight Generation" ],
      [ "explore_opportunity_generation", "Explore Opportunity" ],
      [ "action_result_evaluation", "Action Result Evaluation" ],
      [ "score_snapshot", "Score Snapshot" ],
      [ "data_preparation_queue", "Data Preparation Queue" ],
      [ "meta_evaluation_snapshot", "Meta Evaluation" ],
      [ "calibration", "Learning" ],
      [ "owner_task_digest", "Owner Task Digest" ],
      [ "owner_execution_queue", "Owner Execution Queue" ],
      [ "analysis_orchestration", "Analysis" ],
      [ "business_playbook_update", "Business Playbook" ],
      [ "traffic_channel_recording", "Traffic Channels" ],
      [ "system_mode_snapshot", "System Snapshot" ],
      [ "resource_aware_auto_build", "Resource Auto Build" ],
      [ "auto_revision_queue", "Auto Revision Queue" ],
      [ "pipeline_stuck_detection", "Finish" ]
    ].freeze
    STEP_NAMES = STEP_DEFINITIONS.map(&:first).freeze
    STEP_LABELS = STEP_DEFINITIONS.to_h.freeze
    TERMINAL_STEP_STATUSES = %w[success failed skipped].freeze
    COMPLETED_RUN_STATUSES = %w[success succeeded partial_failed].freeze
    FAILED_RUN_STATUSES = %w[failed stuck].freeze

    StepRow = Data.define(:name, :label, :status, :current) do
      def current?
        current
      end
    end

    Snapshot = Data.define(
      :run,
      :progress_percent,
      :current_step_name,
      :current_step_label,
      :current_business_id,
      :current_business_name,
      :current_business_index,
      :total_business_count,
      :current_candidate_count,
      :total_candidate_count,
      :estimated_finish_at,
      :remaining_seconds,
      :elapsed_seconds,
      :completed_steps,
      :failed_step,
      :failure_reason,
      :retry_count,
      :step_rows,
      :business_count,
      :candidate_count,
      :today_count,
      :revision_queue_count,
      :active,
      :completed,
      :failed
    ) do
      def active?
        active
      end

      def completed?
        completed
      end

      def failed?
        failed
      end

      def status_label
        return "実行中" if active?
        return "Failed" if failed?
        return "Completed" if completed?

        "待機中"
      end

      def elapsed_label
        self.class.duration_label(elapsed_seconds)
      end

      def remaining_label
        return "-" unless active?
        return "1分未満" if remaining_seconds.to_i < 60

        "約#{(remaining_seconds.to_f / 60).ceil}分"
      end

      def business_label
        return "-" if total_business_count.to_i.zero?

        prefix = current_business_name.presence
        counts = "#{current_business_index.to_i} / #{total_business_count.to_i}"
        prefix ? "#{prefix} #{counts}" : counts
      end

      def candidate_label
        return "-" if current_candidate_count.nil?
        return current_candidate_count.to_i.to_s if total_candidate_count.to_i.zero?

        "#{current_candidate_count.to_i} / 約#{total_candidate_count.to_i}"
      end

      def self.duration_label(seconds)
        value = seconds.to_i
        return "0秒" if value <= 0

        hours = value / 3600
        minutes = (value % 3600) / 60
        remaining_seconds = value % 60
        return "#{hours}時間#{minutes}分#{remaining_seconds}秒" if hours.positive?
        return "#{minutes}分#{remaining_seconds}秒" if minutes.positive?

        "#{remaining_seconds}秒"
      end
    end

    def self.call(run, steps: nil, averages: nil, now: Time.current)
      new(
        run,
        steps:,
        averages: averages || historical_averages(excluding_run_ids: [ run.id ]),
        now:
      ).call
    end

    def self.for_runs(runs, now: Time.current)
      records = Array(runs).compact
      return {} if records.empty?

      averages = historical_averages(excluding_run_ids: records.map(&:id))
      records.index_with do |run|
        new(run, steps: loaded_steps_for(run), averages:, now:).call
      end
    end

    def self.historical_averages(excluding_run_ids: [])
      recent_ids = AicooDailyRunStep
        .where(status: "success", step_name: STEP_NAMES)
        .where.not(duration_seconds: nil)
        .where("duration_seconds > 0")
        .order(id: :desc)
        .limit(HISTORY_SAMPLE_LIMIT)
        .select(:id)

      scope = AicooDailyRunStep.where(id: recent_ids)
      scope = scope.where.not(aicoo_daily_run_id: excluding_run_ids) if excluding_run_ids.present?
      scope.group(:step_name).average(:duration_seconds).transform_values(&:to_f)
    end

    def self.loaded_steps_for(run)
      association = run.association(:aicoo_daily_run_steps)
      association.loaded? ? association.target : association.scope.to_a
    end
    private_class_method :loaded_steps_for

    def initialize(run, steps: nil, averages: {}, now: Time.current)
      @run = run
      @steps = Array(steps || self.class.send(:loaded_steps_for, run))
      @averages = averages.to_h.stringify_keys
      @now = now
    end

    def call
      Snapshot.new(
        run:,
        progress_percent:,
        current_step_name: progress_step&.step_name,
        current_step_label: progress_step ? step_label(progress_step.step_name) : "準備中",
        current_business_id: current_progress_metadata["current_business_id"],
        current_business_name: current_progress_metadata["current_business_name"],
        current_business_index: current_progress_metadata["current_business_index"],
        total_business_count: current_progress_metadata["total_business_count"],
        current_candidate_count: candidate_progress[:current],
        total_candidate_count: candidate_progress[:total],
        estimated_finish_at: active? ? now + remaining_seconds : nil,
        remaining_seconds:,
        elapsed_seconds:,
        completed_steps: terminal_steps.map(&:step_name),
        failed_step: failed_step&.step_name,
        failure_reason: failure_reason,
        retry_count: run.retry_count.to_i,
        step_rows:,
        business_count: business_count,
        candidate_count: run.action_candidates_generated_count.to_i,
        today_count: nil,
        revision_queue_count: revision_queue_count,
        active: active?,
        completed: completed?,
        failed: failed?
      )
    end

    private

    attr_reader :run, :steps, :averages, :now

    def latest_steps_by_name
      @latest_steps_by_name ||= steps
        .group_by(&:step_name)
        .transform_values { |records| records.max_by { |step| [ step.started_at || step.created_at, step.id ] } }
    end

    def current_step
      @current_step ||= steps
        .select { |step| step.status == "running" }
        .max_by { |step| [ step.started_at || step.created_at, step.id ] }
    end

    def failed_step
      @failed_step ||= steps
        .select { |step| step.status == "failed" }
        .max_by { |step| [ step.finished_at || step.updated_at, step.id ] }
    end

    def progress_step
      current_step || (failed? ? failed_step : nil)
    end

    def terminal_steps
      @terminal_steps ||= latest_steps_by_name.values.select { |step| TERMINAL_STEP_STATUSES.include?(step.status) }
    end

    def active?
      run.running? || current_step.present?
    end

    def completed?
      COMPLETED_RUN_STATUSES.include?(run.status) && !active?
    end

    def failed?
      FAILED_RUN_STATUSES.include?(run.status) && !active?
    end

    def progress_percent
      return 100 if completed?
      return 0 if run.status == "pending" && steps.empty?

      completed_units = STEP_NAMES.count do |step_name|
        step = latest_steps_by_name[step_name]
        step && TERMINAL_STEP_STATUSES.include?(step.status)
      end
      current_units = current_step ? current_step_fraction : 0
      raw_percent = ((completed_units + current_units) / STEP_NAMES.size.to_f * 100).floor
      active? ? raw_percent.clamp(0, 99) : raw_percent.clamp(0, 100)
    end

    def current_step_fraction
      business_total = current_progress_metadata["total_business_count"].to_i
      business_index = current_progress_metadata["current_business_index"].to_i
      return (business_index.to_f / business_total).clamp(0, MAX_CURRENT_STEP_FRACTION) if business_total.positive?

      expected = expected_duration_for(current_step.step_name)
      return 0 if expected <= 0

      (current_step_elapsed / expected).clamp(0, MAX_CURRENT_STEP_FRACTION)
    end

    def remaining_seconds
      return 0 unless active?

      current_remaining = if current_step
        expected = expected_duration_for(current_step.step_name)
        [ expected * (1 - current_step_fraction), 0 ].max
      else
        0
      end
      future_remaining = STEP_NAMES.sum do |step_name|
        step = latest_steps_by_name[step_name]
        next 0 if step && (TERMINAL_STEP_STATUSES.include?(step.status) || step.status == "running")

        expected_duration_for(step_name)
      end
      (current_remaining + future_remaining).ceil
    end

    def expected_duration_for(step_name)
      historical = averages[step_name].to_f
      return historical if historical.positive?

      same_step_duration = latest_steps_by_name[step_name]&.duration_seconds.to_f
      return same_step_duration if same_step_duration.positive?

      current_run_average_duration
    end

    def current_run_average_duration
      @current_run_average_duration ||= begin
        durations = terminal_steps.filter_map do |step|
          duration = step.duration_seconds.to_f
          duration if duration.positive?
        end
        if durations.any?
          durations.sum / durations.size
        elsif current_step_elapsed.positive?
          [ current_step_elapsed, DEFAULT_STEP_DURATION_SECONDS ].max
        else
          DEFAULT_STEP_DURATION_SECONDS
        end
      end
    end

    def current_step_elapsed
      return 0 unless current_step&.started_at

      [ now - current_step.started_at, 0 ].max
    end

    def elapsed_seconds
      return 0 unless run.started_at

      finish = active? ? now : (run.finished_at || now)
      [ finish - run.started_at, 0 ].max.to_i
    end

    def current_progress_metadata
      @current_progress_metadata ||= begin
        metadata = progress_step&.metadata.to_h.stringify_keys
        insight = metadata["insight_generation_progress"].to_h.stringify_keys
        metadata.merge(
          "current_business_id" => metadata["current_business_id"] || insight["business_id"],
          "current_business_name" => metadata["current_business_name"] || insight["business_name"],
          "current_business_index" => metadata["current_business_index"] || insight["current_business_index"],
          "total_business_count" => metadata["total_business_count"] || insight["business_count"]
        ).compact
      end
    end

    def candidate_progress
      @candidate_progress ||= begin
        return { current: nil, total: nil } unless progress_step&.step_name == "action_generation"

        {
          current: current_progress_metadata["current_candidate_count"].to_i,
          total: current_progress_metadata["total_candidate_count"].to_i
        }
      end
    end

    def business_count
      metadata_count = steps.filter_map do |step|
        metadata = step.metadata.to_h
        insight = metadata["insight_generation_progress"].to_h
        [
          metadata["total_business_count"],
          metadata["target_business_count"],
          metadata["processed_business_count"],
          insight["business_count"]
        ].compact.map(&:to_i).max
      end.max
      (metadata_count || 0).to_i
    end

    def revision_queue_count
      step = latest_steps_by_name["auto_revision_queue"]
      step&.metadata.to_h&.fetch("generated_tasks_count", 0).to_i
    end

    def failure_reason
      run.error_message.presence || failed_step&.error_message.presence
    end

    def step_rows
      STEP_DEFINITIONS.map do |name, label|
        step = latest_steps_by_name[name]
        StepRow.new(
          name:,
          label:,
          status: step&.status || "pending",
          current: step == current_step
        )
      end
    end

    def step_label(name)
      STEP_LABELS.fetch(name, name.to_s.humanize)
    end
  end
end
