require "uri"

module Aicoo
  class BusinessAccessSettingsUpdater
    def initialize(business)
      @business = business
    end

    def update_service!(attributes)
      values = attributes.to_h.deep_stringify_keys
      Business.transaction do
        service = if values["business_service_id"].present?
          business.business_services.find(values["business_service_id"])
        else
          business.business_services.new
        end
        metadata = service.metadata.to_h.merge(
          "branch" => values["branch"].presence || "main",
          "framework" => values["framework"].presence_in(BusinessExecutionProfile::REPOSITORY_TYPES) || "other",
          "health_check_url" => values["health_check_url"].presence,
          "auto_deploy_enabled" => boolean(values["auto_deploy_enabled"]) || false,
          "updated_by" => "owner",
          "updated_at" => Time.current.iso8601
        ).compact
        service.assign_attributes(
          name: values["name"].presence || service.name.presence || business.name,
          url: values["service_url"].presence,
          domain: values["domain"].presence,
          repository: values["github_repository"].presence,
          render_service: values["render_service_name"].presence,
          deploy_target: values["deploy_target"].presence || "render",
          api_endpoint: values["activity_api_endpoint"].presence,
          status: values["status"].presence_in(BusinessService::STATUSES) || service.status,
          metadata:
        )
        service.save!

        sync_primary_service_profile!(service) if primary_service?(service)
      end
    end

    def update_landing_page!(attributes)
      LpIntegration::LandingPageRegistry.new(business:).save!(attributes)
    end

    def update_production!(attributes)
      values = attributes.to_h.deep_stringify_keys
      profile = execution_profile
      profile.assign_attributes(
        production_url: values["production_url"].presence,
        health_check_url: values["health_check_url"].presence,
        render_service_name: values["render_service_name"].presence,
        deploy_target: values["deploy_target"].presence_in(BusinessExecutionProfile::DEPLOY_TARGETS) || profile.deploy_target,
        auto_deploy_enabled: boolean(values["auto_deploy_enabled"]),
        codex_auto_deploy_enabled: boolean(values["auto_deploy_enabled"]),
        active: true
      )
      profile.save!
    end

    def update_measurement!(attributes)
      values = attributes.to_h.deep_stringify_keys
      Business.transaction do
        update_analytics_site!(values)
        update_activity_connection!(values)
        business.update!(metadata: business.metadata.to_h.merge(
          "lp_ga4_measurement_id" => values["ga4_measurement_id"].presence,
          "lp_measurement_updated_at" => Time.current.iso8601
        ).compact)
      end
    end

    private

    attr_reader :business

    def overview
      @overview ||= LpIntegration::Overview.new(business)
    end

    def execution_profile
      business.business_execution_profile || business.build_business_execution_profile
    end

    def update_repository!(repository_url:, branch:, service: nil)
      profile = execution_profile
      repository = repository_url.to_s.strip
      base_branch = branch.presence || "main"
      profile.assign_attributes(
        execution_type: repository.present? ? "external_repo" : profile.execution_type,
        repository_name: repository_name(repository).presence || service&.name.presence || profile.repository_name.presence || business.name,
        repository_type: service&.metadata.to_h&.dig("framework").presence || profile.repository_type,
        github_repository: repository.presence || profile.github_repository,
        codex_repository_url: repository.presence || profile.codex_repository_url,
        default_branch: base_branch,
        codex_base_branch: base_branch,
        production_url: service&.url.presence || profile.production_url,
        health_check_url: service&.metadata.to_h&.dig("health_check_url").presence || profile.health_check_url,
        render_service_name: service&.render_service.presence || profile.render_service_name,
        deploy_target: service&.deploy_target.presence_in(BusinessExecutionProfile::DEPLOY_TARGETS) || profile.deploy_target,
        auto_deploy_enabled: service ? (boolean(service.metadata.to_h["auto_deploy_enabled"]) || false) : profile.auto_deploy_enabled,
        codex_auto_deploy_enabled: service ? (boolean(service.metadata.to_h["auto_deploy_enabled"]) || false) : profile.codex_auto_deploy_enabled,
        active: true
      )
      profile.save!
    end

    def primary_service?(service)
      business.business_services.order(:created_at, :id).first == service
    end

    def sync_primary_service_profile!(service)
      update_repository!(
        repository_url: service.repository,
        branch: service.metadata.to_h["branch"],
        service:
      )
    end

    def update_analytics_site!(values)
      site = AicooAnalyticsSite.where(business:).recent.first
      property_id = values["ga4_property_id"].presence
      gsc_site_url = values["gsc_site_url"].presence
      return if site.nil? && property_id.blank? && gsc_site_url.blank?

      site ||= AicooAnalyticsSite.new(business:, name: "#{business.name} LP共通計測")
      site.assign_attributes(
        name: "#{business.name} LP共通計測",
        public_url: values["public_url"].presence,
        domain: domain_for(values["public_url"]),
        ga4_property_id: property_id,
        gsc_site_url:,
        authentication_mode: "shared",
        enabled: true
      )
      site.save!
    end

    def update_activity_connection!(values)
      connection = overview.activity_connection || business.source_app_connections.new
      enabled = boolean(values["activity_api_enabled"])
      connection.assign_attributes(
        name: "#{business.name} Activity API",
        source_app: connection.source_app.presence || "external_business_#{business.id}",
        connection_type: "external_api",
        status: enabled ? "active" : "inactive",
        enabled:,
        settings: connection.settings.to_h.merge(
          "endpoint_path" => "/api/aicoo/activity_logs",
          "business_id" => business.id,
          "personal_data_policy" => "anonymous_aggregate_only"
        ),
        metadata: connection.metadata.to_h.merge(
          "role" => LpIntegration::Overview::ROLE,
          "managed_by" => "business_access_settings"
        )
      )
      connection.save!
    end

    def domain_for(url)
      URI.parse(url.to_s).host
    rescue URI::InvalidURIError
      nil
    end

    def repository_name(url)
      uri = URI.parse(url.to_s)
      File.basename(uri.path.to_s, ".git")
    rescue URI::InvalidURIError
      url.to_s.split("/").last
    end

    def boolean(value)
      ActiveModel::Type::Boolean.new.cast(value)
    end
  end
end
