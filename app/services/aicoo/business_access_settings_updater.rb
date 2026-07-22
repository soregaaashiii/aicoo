require "uri"

module Aicoo
  class BusinessAccessSettingsUpdater
    LP_STATUSES = %w[draft published paused].freeze

    def initialize(business)
      @business = business
    end

    def update_service!(attributes)
      values = attributes.to_h.deep_stringify_keys
      Business.transaction do
        service = business.business_services.find_by(id: values["business_service_id"].presence) ||
          business.business_services.recent.first ||
          business.business_services.new(name: business.name)
        service.assign_attributes(
          url: values["service_url"].presence,
          domain: values["domain"].presence
        )
        service.save!

        update_repository!(
          repository_url: values["github_repository"],
          branch: values["branch"]
        )
      end
    end

    def update_landing_page!(attributes)
      values = attributes.to_h.deep_stringify_keys
      Business.transaction do
        source_type = values["source_type"].presence_in(LpIntegration::Overview::SOURCE_TYPES.keys) || "manual"
        prototype = overview.source_prototype || business.business_prototypes.new
        metadata = prototype.metadata.to_h.merge(
          "role" => LpIntegration::Overview::ROLE,
          "lp_source_type" => source_type,
          "lp_source_repository_url" => values["source_repository_url"].presence,
          "lp_source_branch" => values["source_branch"].presence || "main",
          "lovable_project_url" => values["lovable_project_url"].presence,
          "lp_source_url" => values["lovable_project_url"].presence || values["public_url"].presence,
          "lp_public_url" => values["public_url"].presence,
          "lp_public_status" => values["public_status"].presence_in(LP_STATUSES) || "draft",
          "updated_by" => "owner",
          "updated_at" => Time.current.iso8601
        ).compact
        prototype.assign_attributes(
          prototype_type: LpIntegration::SettingsUpdater::SOURCE_TYPE_MAP.fetch(source_type),
          name: "LP作成元",
          location: source_location(source_type, values),
          status: "active",
          metadata:
        )
        prototype.save!

        update_repository!(
          repository_url: values["app_repository_url"],
          branch: values["app_branch"]
        )
      end
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

    private

    attr_reader :business

    def overview
      @overview ||= LpIntegration::Overview.new(business)
    end

    def execution_profile
      business.business_execution_profile || business.build_business_execution_profile
    end

    def update_repository!(repository_url:, branch:)
      profile = execution_profile
      repository = repository_url.to_s.strip
      base_branch = branch.presence || "main"
      profile.assign_attributes(
        execution_type: repository.present? ? "external_repo" : profile.execution_type,
        repository_name: repository_name(repository).presence || profile.repository_name.presence || business.name,
        github_repository: repository.presence,
        codex_repository_url: repository.presence,
        default_branch: base_branch,
        codex_base_branch: base_branch,
        active: true
      )
      profile.save!
    end

    def source_location(source_type, values)
      repository = values["source_repository_url"].presence
      lovable_url = values["lovable_project_url"].presence
      public_url = values["public_url"].presence
      return repository || lovable_url || public_url || "ZIP・書き出しコード（未指定）" if source_type == "zip_export"
      return repository || lovable_url || public_url || "手動指定（未設定）" if source_type == "manual"

      repository || lovable_url || public_url || raise(ArgumentError, "LP作成元のURLまたはリポジトリを入力してください。")
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
