module Aicoo
  class LongRunningOperationMonitor
    Operation = Data.define(
      :key,
      :kind,
      :title,
      :status,
      :business_name,
      :started_at,
      :finished_at,
      :duration_seconds,
      :detail,
      :error_message,
      :path,
      :retry_path
    ) do
      def running?
        %w[queued running sent_to_codex].include?(status.to_s)
      end

      def failed?
        %w[failed partial_failed stuck canceled].include?(status.to_s)
      end

      def succeeded?
        %w[success succeeded published paused completed].include?(status.to_s)
      end

      def status_label
        return "実行中" if running?
        return "失敗" if failed?
        return "完了" if succeeded?

        status.to_s.presence || "未実行"
      end

      def duration_label
        seconds = duration_seconds.to_i
        return "-" if seconds <= 0

        minutes = seconds / 60
        return "#{seconds}秒" if minutes.zero?

        hours = minutes / 60
        remaining_minutes = minutes % 60
        return "#{minutes}分" if hours.zero?

        "#{hours}時間#{remaining_minutes}分"
      end

      def compact_message
        source = failed? ? error_message : detail
        source.to_s.lines.first.to_s.strip.truncate(80)
      end
    end

    Result = Data.define(:running_operations, :recent_operations) do
      def running?
        running_operations.any?
      end

      def visible?
        running_operations.any? || recent_operations.any?
      end
    end

    include Rails.application.routes.url_helpers

    def call
      operations = google_api_operations +
        daily_run_operations +
        codex_operations +
        serp_operations +
        data_import_operations +
        landing_page_operations

      running = operations.select(&:running?).sort_by { |operation| operation.started_at || Time.current }.reverse
      recent = operations.reject(&:running?).sort_by { |operation| operation.finished_at || operation.started_at || Time.current }.reverse.first(8)

      Result.new(running, recent)
    end

    private

    def google_api_operations
      GoogleApiImportRun.includes(:business)
        .joins(:business)
        .merge(Business.real_businesses)
        .recent
        .limit(10)
        .map do |run|
        Operation.new(
          key: "google-api-#{run.id}",
          kind: "Google API取得",
          title: "Google API取得#{run.running? ? '中' : ''}",
          status: run.status,
          business_name: run.business.name,
          started_at: run.started_at || run.created_at,
          finished_at: run.finished_at,
          duration_seconds: run.duration_seconds,
          detail: "取得日数 #{run.fetched_days}日 / 更新 #{run.updated_metric_count}件 / #{run.source_types.join(' / ')}",
          error_message: run.error_message,
          path: business_path(run.business, anchor: "business-google"),
          retry_path: business_path(run.business, anchor: "business-google")
        )
      end
    end

    def daily_run_operations
      AicooDailyRun.includes(:aicoo_daily_run_steps).recent.limit(8).map do |run|
        current_step = run.current_step
        Operation.new(
          key: "daily-run-#{run.id}",
          kind: "Daily Run",
          title: run.running? ? "Daily Run実行中" : "Daily Run",
          status: run.status,
          business_name: "AICOO",
          started_at: run.started_at || run.created_at,
          finished_at: run.finished_at,
          duration_seconds: duration_between(run.started_at, run.finished_at),
          detail: "対象日 #{run.target_date} / step #{current_step&.step_name || '-'}",
          error_message: run.error_message,
          path: aicoo_daily_run_path(run),
          retry_path: aicoo_daily_runs_path
        )
      end
    end

    def codex_operations
      AutoRevisionTask.where(status: %w[sent_to_codex running failed canceled])
        .includes(:business)
        .recent
        .limit(8)
        .map do |task|
          Operation.new(
            key: "codex-#{task.id}",
            kind: "Codex実行",
            title: "Codex実行中",
            status: task.status,
            business_name: task.business&.name || "-",
            started_at: task.started_running_at || task.started_at || task.sent_to_codex_at || task.created_at,
            finished_at: task.finished_at,
            duration_seconds: duration_between(task.started_running_at || task.started_at, task.finished_at),
            detail: "risk #{task.risk_level} / priority #{task.priority_score.to_i}",
            error_message: task.error_message,
            path: auto_revision_task_path(task),
            retry_path: auto_revision_task_path(task)
          )
        end
    end

    def serp_operations
      SerpAnalysis.includes(:business)
        .joins(:business)
        .merge(Business.real_businesses)
        .order(analyzed_at: :desc, created_at: :desc)
        .limit(5)
        .map do |analysis|
        Operation.new(
          key: "serp-#{analysis.id}",
          kind: "SERP取得",
          title: analysis.running? ? "SERP走査中" : "SERP走査",
          status: analysis.status,
          business_name: analysis.business.name,
          started_at: analysis.analyzed_at,
          finished_at: analysis.analyzed_at,
          duration_seconds: nil,
          detail: "#{analysis.keyword} / #{analysis.result_count.to_i}件",
          error_message: analysis.error_message,
          path: business_path(analysis.business, anchor: "business-serp"),
          retry_path: business_path(analysis.business, anchor: "business-serp")
        )
      end
    end

    def data_import_operations
      DataImport.includes(:business, :data_source)
        .joins(:business)
        .merge(Business.real_businesses)
        .recent
        .limit(5)
        .map do |data_import|
        Operation.new(
          key: "data-import-#{data_import.id}",
          kind: "データ取込",
          title: "データ取込完了",
          status: "success",
          business_name: data_import.business&.name || "-",
          started_at: data_import.imported_at,
          finished_at: data_import.imported_at,
          duration_seconds: nil,
          detail: "#{data_import.data_source.source_type.upcase} / #{data_import.row_count || 0}行",
          error_message: nil,
          path: data_import.business ? business_path(data_import.business) : dashboard_path,
          retry_path: admin_analytics_imports_path
        )
      end
    end

    def landing_page_operations
      AicooLabLandingPagePublicationEvent.includes(:aicoo_lab_landing_page)
        .order(occurred_at: :desc)
        .limit(5)
        .map do |event|
          page = event.aicoo_lab_landing_page
          Operation.new(
            key: "landing-page-#{event.id}",
            kind: landing_page_kind(event.event_type),
            title: landing_page_title(event),
            status: event.event_type == "pause" ? "paused" : "published",
            business_name: "公開LP",
            started_at: event.occurred_at,
            finished_at: event.occurred_at,
            duration_seconds: nil,
            detail: page.title,
            error_message: nil,
            path: admin_aicoo_lab_edit_public_landing_page_path(page),
            retry_path: admin_aicoo_lab_edit_public_landing_page_path(page)
          )
        end
    end

    def landing_page_kind(event_type)
      case event_type
      when "pause" then "LP停止"
      when "resume" then "LP再公開"
      when "publish" then "LP公開"
      else "LP更新"
      end
    end

    def landing_page_title(event)
      "#{landing_page_kind(event.event_type)}完了"
    end

    def duration_between(started_at, finished_at)
      return unless started_at && finished_at

      (finished_at - started_at).round(2)
    end
  end
end
