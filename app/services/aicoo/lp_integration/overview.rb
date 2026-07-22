module Aicoo
  module LpIntegration
    class Overview
      ROLE = "external_lp_integration".freeze
      SOURCE_TYPES = {
        "lovable_github" => "Lovable GitHub",
        "github" => "GitHub",
        "zip_export" => "ZIP・書き出しコード",
        "figma" => "Figma",
        "public_url" => "公開URL",
        "manual" => "手動指定"
      }.freeze

      attr_reader :business

      def initialize(business)
        @business = business
      end

      def execution_profile
        @execution_profile ||= business.business_execution_profile
      end

      def source_prototype
        @source_prototype ||= business.business_prototypes.active.recent.detect do |prototype|
          prototype.metadata.to_h["role"] == ROLE
        end
      end

      def analytics_site
        @analytics_site ||= AicooAnalyticsSite.where(business:).recent.first
      end

      def activity_connection
        @activity_connection ||= business.source_app_connections.detect do |connection|
          connection.metadata.to_h["role"] == ROLE
        end
      end

      def source_metadata
        source_prototype&.metadata.to_h || {}
      end

      def lp_source_type
        source_metadata["lp_source_type"].presence || "manual"
      end

      def lp_source_type_label
        SOURCE_TYPES.fetch(lp_source_type, lp_source_type)
      end

      def lp_source_repository_url
        source_metadata["lp_source_repository_url"]
      end

      def lp_source_branch
        source_metadata["lp_source_branch"].presence || "main"
      end

      def lp_source_url
        source_metadata["lp_source_url"]
      end

      def app_repository_url
        execution_profile&.effective_codex_repository_url
      end

      def app_branch
        execution_profile&.effective_codex_base_branch || "main"
      end

      def app_framework
        execution_profile&.repository_type.presence || "other"
      end

      def marketing_root_path
        source_metadata["marketing_root_path"]
      end

      def production_url
        execution_profile&.production_url
      end

      def render_service_name
        execution_profile&.render_service_name
      end

      def ga4_property_id
        analytics_site&.ga4_property_id
      end

      def ga4_measurement_id
        source_metadata["ga4_measurement_id"]
      end

      def gsc_site_url
        analytics_site&.gsc_site_url
      end

      def integration_enabled?
        ActiveModel::Type::Boolean.new.cast(source_metadata["integration_enabled"])
      end

      def activity_api_enabled?
        integration_enabled? && activity_connection&.enabled? && activity_connection&.status == "active"
      end

      def auto_deploy_enabled?
        execution_profile&.auto_deploy_enabled? || false
      end

      def manual_approval_required?
        execution_profile.nil? || execution_profile.require_manual_approval?
      end

      def latest_task
        sync_tasks.first
      end

      def latest_successful_task
        sync_tasks.find(&:successful_result?)
      end

      def sync_tasks
        @sync_tasks ||= business.auto_revision_tasks
          .includes(:codex_submission, :auto_revision_executions)
          .order(created_at: :desc)
          .select { |task| task.metadata.to_h["workflow_type"] == "external_lp_import" }
          .first(30)
      end

      def last_sync_at
        latest_successful_task&.finished_at
      end

      def last_sync_commit_sha
        task_commit_sha(latest_successful_task)
      end

      def last_deployed_at
        sync_tasks.filter_map do |task|
          parse_time(task.codex_submission&.response_payload.to_h["deployed_at"])
        end.first
      end

      def latest_execution(task)
        task.auto_revision_executions.max_by(&:created_at)
      end

      def task_commit_sha(task)
        return if task.nil?

        task.codex_submission&.response_payload.to_h["commit_sha"].presence ||
          latest_execution(task)&.commit_sha.presence ||
          task.metadata.to_h.dig("result", "commit_sha")
      end

      def task_deploy_status(task)
        task.codex_submission&.deploy_status.presence || latest_execution(task)&.deploy_status.presence || "未実施"
      end

      def task_status_label(task)
        {
          "draft" => "下書き",
          "waiting_approval" => "承認待ち",
          "approved" => "承認済み",
          "queued" => "実行待ち",
          "ready_for_codex" => "Codex準備済み",
          "sent_to_codex" => "Codex送信済み",
          "running" => "実行中",
          "completed" => "完了",
          "succeeded" => "成功",
          "partial_succeeded" => "一部成功",
          "failed" => "失敗",
          "canceled" => "取消"
        }.fetch(task.status, task.status)
      end

      def last_verified_at
        parse_time(source_metadata["last_verified_at"])
      end

      def last_error
        source_metadata["last_error"].presence || latest_task&.error_message.presence || latest_task&.codex_submission&.error_message.presence
      end

      def ga4_summary
        @ga4_summary ||= Aicoo::BusinessGoogleConnectionSummary.new(business, source_key: "ga4").call
      end

      def gsc_summary
        @gsc_summary ||= Aicoo::BusinessGoogleConnectionSummary.new(business, source_key: "gsc").call
      end

      def metrics_30d
        @metrics_30d ||= begin
          rows = business.business_metric_dailies.where(recorded_on: 29.days.ago.to_date..Date.current)
          impressions = rows.sum(:impressions)
          clicks = rows.sum(:clicks)
          positions = rows.where("impressions > 0").pluck(:average_position).map(&:to_d)
          {
            impressions:,
            clicks:,
            ctr: impressions.positive? ? clicks.to_d / impressions : nil,
            average_position: positions.any? ? positions.sum / positions.size : nil
          }
        end
      end

      def source_reference_present?
        lp_source_repository_url.present? || lp_source_url.present? || source_prototype&.location.present?
      end

      def activity_api_status_label
        return "連携OFF" unless integration_enabled?
        return "接続済み" if activity_api_enabled?
        return "設定要確認" if activity_connection

        "未設定"
      end

      private

      def parse_time(value)
        Time.zone.parse(value.to_s) if value.present?
      rescue ArgumentError
        nil
      end
    end
  end
end
