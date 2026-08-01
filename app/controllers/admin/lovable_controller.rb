module Admin
  class LovableController < ApplicationController
    def show
      @result = Aicoo::Lovable::PipelineDiagnostic.new(probe: params[:probe] == "1").call
      @build_url_result = Aicoo::Lovable::BuildUrlDiagnostic.new.call
      load_github_webhook_configuration
      @latest_runs = AicooLabGenerationRun.where(generation_type: "lp_generation").recent.select do |run|
        run.metadata.to_h["pipeline"] == "lovable"
      end.first(50)
    end

    def update_cloudflare
      redirect_to admin_cloudflare_connection_path, notice: "Cloudflare認証はAICOO全体設定へ統合されました。"
    end

    def update_github_webhook
      values = params.expect(github_webhook: %i[secret])
      github_webhook_configuration.update_secret!(values[:secret])
      redirect_to admin_lovable_path(anchor: "github-webhook-settings"), notice: "GitHub Webhook設定を保存しました。"
    rescue ActiveRecord::RecordInvalid => e
      redirect_to admin_lovable_path(anchor: "github-webhook-settings"), alert: "GitHub Webhook設定を保存できませんでした: #{e.record.errors.full_messages.to_sentence}"
    end

    private

    def load_github_webhook_configuration
      @github_webhook_configuration = github_webhook_configuration
      @github_webhook_diagnostics = @github_webhook_configuration.diagnostics
      @github_webhook_url = github_webhook_url
    end

    def github_webhook_configuration
      @github_webhook_configuration ||= Aicoo::Lovable::GithubWebhookConfiguration.new(profile: github_webhook_profile)
    end

    def github_webhook_profile
      DataSourceCostProfile.find_or_initialize_by(source_key: Aicoo::Lovable::GithubWebhookConfiguration::PROFILE_KEY) do |profile|
        profile.name = "Lovable GitHub Webhook"
        profile.execution_mode = "auto"
        profile.enabled = true
      end
    end

  end
end
