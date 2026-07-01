module Admin
  class BusinessExecutionProfilesController < ApplicationController
    before_action :set_business_execution_profile, only: %i[edit update]

    def index
      @business_execution_profiles = BusinessExecutionProfile.includes(:business).order(updated_at: :desc)
    end

    def new
      @business_execution_profile = BusinessExecutionProfile.new(business_id: params[:business_id])
    end

    def create
      @business_execution_profile = BusinessExecutionProfile.new(business_execution_profile_params)

      if @business_execution_profile.save
        redirect_to admin_business_execution_profiles_path, notice: "Execution Profileを作成しました。"
      else
        render :new, status: :unprocessable_entity
      end
    end

    def edit
    end

    def update
      if @business_execution_profile.update(business_execution_profile_params)
        redirect_to admin_business_execution_profiles_path, notice: "Execution Profileを更新しました。"
      else
        render :edit, status: :unprocessable_entity
      end
    end

    private

    def set_business_execution_profile
      @business_execution_profile = BusinessExecutionProfile.find(params.expect(:id))
    end

    def business_execution_profile_params
      params.expect(
        business_execution_profile: [
          :business_id,
          :execution_type,
          :repository_name,
          :repository_type,
          :repository_path,
          :github_repository,
          :target_slug,
          :target_paths_text,
          :default_branch,
          :working_branch_prefix,
          :test_command,
          :lint_command,
          :deploy_command,
          :deploy_target,
          :render_service_name,
          :production_url,
          :health_check_url,
          :codex_instructions,
          :forbidden_patterns,
          :auto_deploy_enabled,
          :auto_merge_enabled,
          :auto_deploy_risk_limit,
          :require_manual_approval,
          :active
        ]
      )
    end
  end
end
