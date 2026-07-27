module Admin
  class LovableController < ApplicationController
    def show
      @result = Aicoo::Lovable::PipelineDiagnostic.new(probe: params[:probe] == "1").call
      @build_url_result = Aicoo::Lovable::BuildUrlDiagnostic.new.call
      load_cloudflare_configuration
      load_github_webhook_configuration
      @latest_runs = AicooLabGenerationRun.where(generation_type: "lp_generation").recent.select do |run|
        run.metadata.to_h["pipeline"] == "lovable"
      end.first(50)
    end

    def update_cloudflare
      profile = cloudflare_profile
      values = params.expect(cloudflare_pages: %i[account_id api_token project_name])
      credentials = profile.credentials.merge(
        "account_id" => values[:account_id].presence || profile.credentials["account_id"],
        "api_token" => values[:api_token].presence || profile.credentials["api_token"],
        "project_name" => values[:project_name].presence || profile.credentials["project_name"] || "aicoo-lp"
      ).compact
      profile.update!(
        name: "Cloudflare Pages",
        execution_mode: "auto",
        enabled: true,
        metadata: profile.metadata.to_h.merge("credentials" => credentials)
      )
      redirect_to admin_lovable_path(anchor: "cloudflare-pages-settings"), notice: "Cloudflare Pages設定を保存しました。"
    rescue ActiveRecord::RecordInvalid => e
      redirect_to admin_lovable_path(anchor: "cloudflare-pages-settings"), alert: "Cloudflare Pages設定を保存できませんでした: #{e.record.errors.full_messages.to_sentence}"
    end

    def update_github_webhook
      values = params.expect(github_webhook: %i[secret])
      github_webhook_configuration.update_secret!(values[:secret])
      redirect_to admin_lovable_path(anchor: "github-webhook-settings"), notice: "GitHub Webhook設定を保存しました。"
    rescue ActiveRecord::RecordInvalid => e
      redirect_to admin_lovable_path(anchor: "github-webhook-settings"), alert: "GitHub Webhook設定を保存できませんでした: #{e.record.errors.full_messages.to_sentence}"
    end

    private

    def load_cloudflare_configuration
      @cloudflare_profile = cloudflare_profile
      @cloudflare_configuration = Aicoo::CloudflarePages::Configuration.new(profile: @cloudflare_profile)
    end

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

    def cloudflare_profile
      DataSourceCostProfile.find_or_initialize_by(source_key: Aicoo::CloudflarePages::Configuration::PROFILE_KEY) do |profile|
        profile.name = "Cloudflare Pages"
        profile.execution_mode = "auto"
        profile.enabled = true
      end
    end
  end
end
