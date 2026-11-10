require "uri"
require "securerandom"

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
        service_url = values.key?("service_url") ? values["service_url"].presence : service.url
        admin_url = values.key?("admin_url") ? values["admin_url"].presence : service.admin_url
        other_url = values.key?("other_url") ? values["other_url"].presence : service.other_url
        metadata = service.metadata.to_h.merge(
          "branch" => values["branch"].presence || "main",
          "framework" => values["framework"].presence_in(BusinessExecutionProfile::REPOSITORY_TYPES) || "other",
          "admin_url" => admin_url,
          "other_url" => other_url,
          "user_page_analysis_enabled" => page_analysis_enabled(values, service, "user", service_url, default: true),
          "admin_page_analysis_enabled" => page_analysis_enabled(values, service, "admin", admin_url, default: false),
          "other_page_analysis_enabled" => page_analysis_enabled(values, service, "other", other_url, default: false),
          "health_check_url" => values["health_check_url"].presence,
          "auto_deploy_enabled" => boolean(values["auto_deploy_enabled"]) || false,
          "updated_by" => "owner",
          "updated_at" => Time.current.iso8601
        ).compact
        service.assign_attributes(
          name: values["name"].presence || service.name.presence || business.name,
          url: service_url,
          domain: values["domain"].presence,
          stripe_account: values["stripe_account"].presence,
          repository: values["github_repository"].presence,
          render_service: values["render_service_name"].presence,
          deploy_target: values["deploy_target"].presence || "render",
          api_endpoint: values["activity_api_endpoint"].presence,
          status: values["status"].presence_in(BusinessService::STATUSES) || service.status,
          metadata:
        )
        service.save!

        sync_primary_service_profile!(service) if primary_service?(service)
        service
      end
    end

    def create_service_page!(service_id:, attributes:)
      values = attributes.to_h.deep_stringify_keys
      Business.transaction do
        service = business.business_services.find(service_id)
        name, url = normalized_additional_page_values(values)
        ensure_unique_additional_page_url!(service, url)
        pages = service.stored_additional_pages
        pages << {
          "id" => SecureRandom.uuid,
          "name" => name,
          "url" => url,
          "analysis_enabled" => boolean(values["analysis_enabled"])
        }
        save_additional_pages!(service, pages)
      end
    end

    def update_service_page!(service_id:, page_id:, attributes:)
      values = attributes.to_h.deep_stringify_keys
      Business.transaction do
        service = business.business_services.find(service_id)
        name, url = normalized_additional_page_values(values)
        ensure_unique_additional_page_url!(service, url, except_page_id: page_id)

        if page_id.to_s.in?(%w[admin other])
          metadata = service.metadata.to_h.merge(
            "#{page_id}_page_name" => name,
            "#{page_id}_url" => url,
            "#{page_id}_page_analysis_enabled" => boolean(values["analysis_enabled"]),
            "updated_by" => "owner",
            "updated_at" => Time.current.iso8601
          )
          service.update!(metadata:)
        else
          pages = service.stored_additional_pages
          page = pages.find { |entry| entry["id"].to_s == page_id.to_s }
          raise ArgumentError, "追加ページが見つかりません。" unless page

          page.merge!(
            "name" => name,
            "url" => url,
            "analysis_enabled" => boolean(values["analysis_enabled"])
          )
          save_additional_pages!(service, pages)
        end
      end
    end

    def destroy_service_page!(service_id:, page_id:)
      id = page_id.to_s
      raise ArgumentError, "ユーザーページはServiceの登録URLとして管理されるため削除できません。" if id == "user"

      Business.transaction do
        service = business.business_services.find(service_id)
        if id.in?(%w[admin other])
          metadata = service.metadata.to_h.merge(
            "#{id}_page_analysis_enabled" => false,
            "#{id}_url" => nil,
            "#{id}_page_name" => nil,
            "updated_by" => "owner",
            "updated_at" => Time.current.iso8601
          )
          service.update!(metadata: metadata.compact)
        else
          pages = service.stored_additional_pages
          filtered_pages = pages.reject { |entry| entry["id"].to_s == id }
          raise ArgumentError, "追加ページが見つかりません。" if filtered_pages.size == pages.size

          save_additional_pages!(service, filtered_pages)
        end
        service
      end
    end

    def update_landing_page!(attributes)
      LpIntegration::LandingPageRegistry.new(business:).update_owner_settings!(attributes)
    end

    def update_campaign!(attributes)
      values = attributes.to_h.deep_stringify_keys
      campaign = values["campaign_id"].present? ? business.business_campaigns.find(values["campaign_id"]) : business.business_campaigns.new
      campaign.assign_attributes(
        name: values["name"],
        campaign_type: values["campaign_type"].presence_in(BusinessCampaign::CAMPAIGN_TYPES) || "other",
        status: values["status"].presence_in(BusinessCampaign::STATUSES) || "active",
        starts_on: values["starts_on"].presence,
        ends_on: values["ends_on"].presence,
        budget_yen: integer_or_nil(values["budget_yen"]),
        target_conversions: decimal_or_nil(values["target_conversions"]),
        target_cpa_yen: integer_or_nil(values["target_cpa_yen"]),
        ga4_filter: values["ga4_filter"].presence,
        gsc_filter: values["gsc_filter"].presence,
        notes: values["notes"].presence
      )
      campaign.save!
      campaign
    end

    def archive_campaign!(campaign_id)
      campaign = business.business_campaigns.find(campaign_id)
      raise ArgumentError, "LPが登録されているCampaignはアーカイブできません。" if campaign.landing_pages.active.exists?

      campaign.update!(status: "archived")
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

    def update_cloudflare!(attributes)
      values = attributes.to_h.deep_stringify_keys
      configuration = CloudflarePages::Configuration.new(business:)
      project_name = values["project_name"].to_s.strip
      raise ArgumentError, "Cloudflare Pages Projectを選択してください。" if project_name.blank?

      project = configuration.project_snapshot_for(project_name)
      if configuration.available_projects.any? && project.nil?
        raise ArgumentError, "選択したCloudflare Pages Projectを全体設定で確認できません。"
      end

      production_url = values["production_url"].presence || project&.dig("production_url").presence || "https://#{project_name}.pages.dev"
      allowed_urls = ([ project&.dig("production_url") ] + Array(project&.dig("domains")).map { |domain| "https://#{domain}" }).compact
      if allowed_urls.any? && !allowed_urls.include?(production_url)
        raise ArgumentError, "選択した公開ドメインはPages Projectに登録されていません。"
      end

      setting = BusinessDataSourceSetting.for_business_and_source(business, CloudflarePages::Configuration::PROFILE_KEY)
      secret_keys = %w[account_id api_token access_token refresh_token token_expires_at oauth_scope]
      metadata = setting.metadata.to_h.except(*secret_keys)
      credentials = metadata.fetch("credentials", {}).to_h.except("project_name", *secret_keys)
      connection_fields = metadata.fetch("connection_fields", {}).to_h.except("project_name", *secret_keys)
      metadata["credentials"] = credentials
      metadata.delete("credentials") if credentials.empty?
      metadata["connection_fields"] = connection_fields
      metadata.delete("connection_fields") if connection_fields.empty?
      setting.assign_attributes(
        enabled: true,
        connection_status: configuration.globally_connected? ? "linked" : "needs_attention",
        property_identifier: project_name,
        endpoint_url: production_url,
        credential_reference: "AICOO全体Cloudflare認証",
        metadata: metadata.merge(
          "source_binding" => metadata.fetch("source_binding", {}).to_h.merge("use_global" => "1"),
          "project_name" => project_name,
          "production_url" => production_url
        )
      )
      setting.save!
      setting
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
        production_url: service ? service.url.presence : profile.production_url,
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

    def page_analysis_enabled(values, service, kind, page_url, default:)
      return false if page_url.blank?

      key = "#{kind}_page_analysis_enabled"
      return boolean(values[key]) if values.key?(key)

      metadata = service.metadata.to_h
      metadata.key?(key) ? boolean(metadata[key]) : default
    end

    def normalized_additional_page_values(values)
      name = values["name"].to_s.strip
      url = values["url"].to_s.strip
      raise ArgumentError, "ページ名を入力してください。" if name.blank?
      raise ArgumentError, "URLを入力してください。" if url.blank?

      uri = URI.parse(url)
      raise ArgumentError, "URLはhttp://またはhttps://で入力してください。" unless uri.is_a?(URI::HTTP) && uri.host.present?

      [ name, url ]
    rescue URI::InvalidURIError
      raise ArgumentError, "URLの形式が正しくありません。"
    end

    def ensure_unique_additional_page_url!(service, url, except_page_id: nil)
      duplicate = service.page_configurations.any? do |page|
        page[:id].to_s != except_page_id.to_s && page[:url].to_s == url
      end
      raise ArgumentError, "同じURLのページがすでに登録されています。" if duplicate
    end

    def save_additional_pages!(service, pages)
      service.update!(
        metadata: service.metadata.to_h.merge(
          "additional_pages" => pages,
          "updated_by" => "owner",
          "updated_at" => Time.current.iso8601
        )
      )
      service
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

    def integer_or_nil(value)
      Integer(value, exception: false) if value.present?
    end

    def decimal_or_nil(value)
      BigDecimal(value.to_s) if value.present?
    rescue ArgumentError
      nil
    end
  end
end
