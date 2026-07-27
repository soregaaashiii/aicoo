require "json"
require "net/http"
require "uri"

module Aicoo
  module CloudflarePages
    class DeploymentVerifier
      Result = Data.define(:completed, :status, :deployment_id, :url, :message)

      def initialize(configuration: Configuration.new, http_adapter: nil)
        @configuration = configuration
        @http_adapter = http_adapter || method(:perform_http)
      end

      def call(landing_page:, commit_sha:, deleted: false)
        raise ArgumentError, "公開確認に必要なGit commit SHAがありません。" if commit_sha.blank?

        deployment = cloudflare_deployment(commit_sha)
        return pending("Cloudflare Pagesのdeploymentを待っています。") if configuration.cloudflare_api_configured? && deployment.blank?

        status = deployment&.dig("latest_stage", "status").presence || deployment&.dig("stages", -1, "status")
        return failed(deployment, status) if status.in?(%w[failure failed])
        return pending("Cloudflare Pagesのbuild完了を待っています。") if deployment && status != "success"

        url = landing_page.metadata.to_h["cloudflare_url"].presence || landing_page.landing_page_url
        response = fetch_url(url)
        verified = deleted ? response.code.to_i == 404 : response.is_a?(Net::HTTPSuccess)
        return pending(deleted ? "Cloudflare Pagesからの削除反映を待っています。" : "Cloudflare Pagesの公開URL反映を待っています。") unless verified

        complete!(landing_page, deployment, url, deleted:)
      rescue StandardError => e
        pending("公開確認に失敗しました: #{e.message}")
      end

      private

      attr_reader :configuration, :http_adapter

      def cloudflare_deployment(commit_sha)
        return unless configuration.cloudflare_api_configured?

        uri = URI("https://api.cloudflare.com/client/v4/accounts/#{configuration.account_id}/pages/projects/#{configuration.project_name}/deployments?env=production&per_page=20")
        request = Net::HTTP::Get.new(uri)
        request["Authorization"] = "Bearer #{configuration.api_token}"
        request["Content-Type"] = "application/json"
        response = http_adapter.call(uri, request)
        body = JSON.parse(response.body.presence || "{}")
        raise ArgumentError, body["errors"].to_s if body["success"] == false || !response.is_a?(Net::HTTPSuccess)

        Array(body["result"]).find do |deployment|
          deployed_sha = deployment.dig("deployment_trigger", "metadata", "commit_hash").to_s
          deployed_sha.present? &&
            (commit_sha.to_s.start_with?(deployed_sha) || deployed_sha.start_with?(commit_sha.to_s))
        end
      end

      def fetch_url(value)
        uri = URI(value)
        request = Net::HTTP::Get.new(uri)
        http_adapter.call(uri, request)
      end

      def complete!(landing_page, deployment, url, deleted:)
        now = Time.current
        metadata = landing_page.metadata.to_h.merge(
          "cloudflare_deploy_status" => deleted ? "deleted" : "deployed",
          "cloudflare_deployment_id" => deployment&.dig("id"),
          "last_published_at" => now.iso8601,
          "last_sync_at" => now.iso8601,
          "sync_status" => "synced",
          "planning_status" => deleted ? "archived" : "improvement_pending",
          "pipeline_stage" => deleted ? "completed" : "improvement_pending",
          "pipeline_stages" => Aicoo::LpIntegration::LandingPagePipelineState.build(
            current: deleted ? "completed" : "improvement_pending",
            approval_required: false
          )
        ).compact
        metadata["lp_public_status"] = "published" unless deleted
        landing_page.update!(metadata:)
        stamp_generation_run!(landing_page, url, deployment) unless deleted
        Result.new(
          completed: true,
          status: deleted ? "deleted" : "deployed",
          deployment_id: deployment&.dig("id"),
          url:,
          message: deleted ? "Cloudflare PagesからLPを削除しました。" : "Cloudflare PagesでLPを公開しました。"
        )
      end

      def stamp_generation_run!(landing_page, url, deployment)
        run_id = landing_page.metadata.to_h["lovable_generation_run_id"]
        run = AicooLabGenerationRun.find_by(id: run_id)
        return unless run

        publication = run.metadata.to_h.fetch("publication", {}).merge(
          "status" => "published",
          "published" => true,
          "production_url" => url,
          "deploy_id" => deployment&.dig("id"),
          "published_at" => Time.current.iso8601,
          "last_synced_at" => Time.current.iso8601
        ).compact
        run.update!(metadata: run.metadata.to_h.merge("publication" => publication))
      end

      def failed(deployment, status)
        Result.new(
          completed: false,
          status: "failed",
          deployment_id: deployment&.dig("id"),
          url: deployment&.dig("url"),
          message: "Cloudflare Pages deploymentが#{status}になりました。"
        )
      end

      def pending(message)
        Result.new(completed: false, status: "pending", deployment_id: nil, url: nil, message:)
      end

      def perform_http(uri, request)
        Net::HTTP.start(uri.hostname, uri.port, use_ssl: uri.scheme == "https", open_timeout: 10, read_timeout: 20) do |http|
          http.request(request)
        end
      end
    end
  end
end
