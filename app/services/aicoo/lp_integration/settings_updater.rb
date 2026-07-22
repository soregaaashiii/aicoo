require "uri"

module Aicoo
  module LpIntegration
    class SettingsUpdater
      SOURCE_TYPE_MAP = {
        "lovable_github" => "github",
        "github" => "github",
        "zip_export" => "other",
        "figma" => "figma",
        "public_url" => "url",
        "manual" => "other"
      }.freeze

      def initialize(business:, attributes:)
        @business = business
        @attributes = attributes.to_h.deep_stringify_keys
      end

      def call
        Business.transaction do
          update_execution_profile!
          update_source_prototype!
          update_analytics_site!
          update_activity_connection!
        end

        Overview.new(business)
      end

      private

      attr_reader :business, :attributes

      def update_execution_profile!
        profile = business.business_execution_profile || business.build_business_execution_profile
        repository_url = attributes["app_repository_url"].to_s.strip
        branch = attributes["app_branch"].presence || "main"
        framework = attributes["app_framework"].presence_in(BusinessExecutionProfile::REPOSITORY_TYPES) || "other"
        profile.assign_attributes(
          execution_type: "external_repo",
          repository_name: repository_name(repository_url).presence || profile.repository_name.presence || business.name,
          repository_type: framework,
          github_repository: repository_url.presence,
          default_branch: branch,
          production_url: attributes["production_url"].presence,
          render_service_name: attributes["render_service_name"].presence,
          health_check_url: attributes["health_check_url"].presence,
          deploy_target: attributes["render_service_name"].present? ? "render" : profile.deploy_target,
          codex_enabled: boolean("integration_enabled"),
          codex_project_folder: profile.codex_project_folder.presence || repository_name(repository_url).presence,
          codex_repository_url: repository_url.presence,
          codex_base_branch: branch,
          auto_deploy_enabled: boolean("auto_deploy_enabled"),
          codex_auto_deploy_enabled: boolean("auto_deploy_enabled"),
          require_manual_approval: boolean("manual_approval_required"),
          active: true
        )
        profile.save!
      end

      def update_source_prototype!
        overview = Overview.new(business)
        prototype = overview.source_prototype || business.business_prototypes.new
        source_type = attributes["lp_source_type"].presence_in(Overview::SOURCE_TYPES.keys) || "manual"
        metadata = prototype.metadata.to_h.merge(
          "role" => Overview::ROLE,
          "lp_source_type" => source_type,
          "lp_source_repository_url" => attributes["lp_source_repository_url"].presence,
          "lp_source_branch" => attributes["lp_source_branch"].presence || "main",
          "lp_source_url" => attributes["lp_source_url"].presence,
          "marketing_root_path" => attributes["marketing_root_path"].presence,
          "ga4_measurement_id" => attributes["ga4_measurement_id"].presence,
          "integration_enabled" => boolean("integration_enabled"),
          "activity_api_enabled" => boolean("activity_api_enabled"),
          "updated_by" => "owner",
          "updated_at" => Time.current.iso8601
        ).compact
        prototype.assign_attributes(
          prototype_type: SOURCE_TYPE_MAP.fetch(source_type),
          name: "LP作成元",
          location: source_location(source_type),
          status: "active",
          metadata:
        )
        prototype.save!
      end

      def update_analytics_site!
        site = AicooAnalyticsSite.where(business:).recent.first
        property_id = attributes["ga4_property_id"].presence
        gsc_site_url = attributes["gsc_site_url"].presence
        return if site.nil? && property_id.blank? && gsc_site_url.blank?

        site ||= AicooAnalyticsSite.new(business:, name: business.name)
        previous_ga4_setting = site.ga4_setting
        previous_gsc_setting = site.gsc_setting
        site.assign_attributes(
          name: business.name,
          ga4_property_id: property_id,
          gsc_site_url:,
          authentication_mode: "shared",
          enabled: true
        )
        site.save!
        previous_ga4_setting&.update!(enabled: false) if property_id.blank?
        previous_gsc_setting&.update!(enabled: false) if gsc_site_url.blank?
      end

      def update_activity_connection!
        overview = Overview.new(business)
        connection = overview.activity_connection || business.source_app_connections.new
        enabled = boolean("integration_enabled") && boolean("activity_api_enabled")
        connection.assign_attributes(
          name: "#{business.name} Activity API",
          source_app: connection.source_app.presence || "external_lp_#{business.id}",
          connection_type: "external_api",
          status: enabled ? "active" : "inactive",
          enabled:,
          settings: connection.settings.to_h.merge(
            "endpoint_path" => "/api/aicoo/activity_logs",
            "business_id" => business.id,
            "personal_data_policy" => "anonymous_aggregate_only",
            "integration_enabled" => boolean("integration_enabled")
          ),
          metadata: connection.metadata.to_h.merge(
            "role" => Overview::ROLE,
            "managed_by" => "lp_integration"
          )
        )
        connection.save!
      end

      def source_location(source_type)
        repository = attributes["lp_source_repository_url"].presence
        source_url = attributes["lp_source_url"].presence
        return repository || source_url || "ZIP・書き出しコード（未指定）" if source_type == "zip_export"
        return repository || source_url || "手動指定（未設定）" if source_type == "manual"

        repository || source_url || raise(ArgumentError, "LP作成元のURLまたはリポジトリを入力してください。")
      end

      def repository_name(url)
        uri = URI.parse(url.to_s)
        File.basename(uri.path.to_s, ".git")
      rescue URI::InvalidURIError
        url.to_s.split("/").last
      end

      def boolean(key)
        ActiveModel::Type::Boolean.new.cast(attributes[key])
      end
    end
  end
end
