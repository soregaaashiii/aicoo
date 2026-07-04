module Aicoo
  class NewBusinessAutomationDefaults
    DEFAULT_REPOSITORY_URL = "https://github.com/soregaaashiii/aicoo".freeze

    def initialize(business)
      @business = business
    end

    def self.apply!(business)
      new(business).apply!
    end

    def apply!
      return business unless eligible?

      original_status = business.status
      business.update!(business_defaults)
      business.update_column(:status, original_status) if original_status.present? && business.status != original_status
      ensure_execution_profile!
      business
    end

    private

    attr_reader :business

    def eligible?
      business.created_by_aicoo? &&
        !business.system_business? &&
        business.lifecycle_stage.in?(%w[idea lp_validation mvp]) &&
        !business.production_like_business?
    end

    def business_defaults
      {
        daily_run_enabled: true,
        serp_enabled: true,
        auto_revision_mode: "automatic",
        auto_deploy_mode: "approval",
        auto_build_enabled: true,
        auto_build_requires_approval: false,
        auto_build_risk_level: "low",
        new_lp_auto_deploy_enabled: true,
        business_type: business.business_type.presence || "landing_page",
        metadata: business.metadata.to_h.merge(
          "new_business_defaults_applied" => true,
          "new_business_defaults_applied_at" => Time.current.iso8601,
          "codex_auto_submit_default" => true
        )
      }
    end

    def ensure_execution_profile!
      profile = business.business_execution_profile || business.build_business_execution_profile
      profile.assign_attributes(execution_profile_defaults)
      profile.save!
    end

    def execution_profile_defaults
      repository_url = ENV["AICOO_INTERNAL_GITHUB_REPO"].presence || DEFAULT_REPOSITORY_URL
      {
        execution_type: "aicoo_internal",
        repository_name: "aicoo",
        repository_type: "rails",
        repository_path: ENV["AICOO_INTERNAL_PROJECT_PATH"].presence || Rails.root.to_s,
        github_repository: repository_url,
        default_branch: "main",
        working_branch_prefix: "codex/auto-revision",
        target_slug: business.send(:source_target_slug),
        target_paths: business.send(:aicoo_internal_target_paths),
        test_command: "bin/rails test",
        lint_command: "bin/rails zeitwerk:check",
        deploy_command: "Render auto deploy after GitHub merge",
        active: true,
        require_manual_approval: false,
        auto_deploy_enabled: false,
        auto_merge_enabled: false,
        auto_deploy_risk_limit: "low",
        codex_enabled: true,
        codex_workspace_name: ENV["AICOO_CODEX_WORKSPACE"].presence || "AICOO",
        codex_project_folder: ENV["AICOO_CODEX_PROJECT_FOLDER"].presence || "/workspace/aicoo",
        codex_repository_url: repository_url,
        codex_base_branch: "main",
        codex_working_branch_prefix: "aicoo/",
        codex_auto_submit_enabled: true,
        codex_auto_pr_enabled: true,
        codex_auto_merge_enabled: false,
        codex_auto_deploy_enabled: false,
        codex_risk_limit: "medium"
      }
    end
  end
end
