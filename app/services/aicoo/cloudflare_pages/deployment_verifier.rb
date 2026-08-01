require "json"
require "net/http"
require "nokogiri"
require "uri"

module Aicoo
  module CloudflarePages
    class DeploymentVerifier
      Result = Data.define(:completed, :status, :deployment_id, :url, :message)
      ConnectionResult = Data.define(:ok, :code, :project_name, :http_status, :message)
      PageVerification = Data.define(:ok, :title, :message)

      def initialize(configuration: Configuration.new, http_adapter: nil)
        @configuration = configuration
        @http_adapter = http_adapter || method(:perform_http)
      end

      def call(landing_page:, commit_sha:, deleted: false)
        raise ArgumentError, "公開確認に必要なGit commit SHAがありません。" if commit_sha.blank?

        @active_configuration = configuration.for_business(landing_page.business)

        deployment = cloudflare_deployment(commit_sha)
        return pending("Cloudflare Pagesのdeploymentを待っています。") if active_configuration.cloudflare_api_configured? && deployment.blank?

        status = deployment&.dig("latest_stage", "status").presence || deployment&.dig("stages", -1, "status")
        return failed(deployment, status) if status.in?(%w[failure failed])
        return pending("Cloudflare Pagesのbuild完了を待っています。") if deployment && status != "success"

        url = landing_page.metadata.to_h["cloudflare_url"].presence || landing_page.landing_page_url
        response = fetch_url(url)
        if deleted
          return pending("Cloudflare Pagesからの削除反映を待っています。") unless response.code.to_i == 404

          return complete!(landing_page, deployment, url, response:, deleted:, page_title: nil)
        end
        verification = verify_public_page(response)
        return pending(verification.message) unless verification.ok

        complete!(landing_page, deployment, url, response:, deleted:, page_title: verification.title)
      rescue StandardError => e
        pending("公開確認に失敗しました: #{e.message}")
      end

      def check_connection(business: nil)
        @active_configuration = business ? configuration.for_business(business) : configuration
        return connection_failure("account_id_missing", "Cloudflare Account IDが未設定です。") if active_configuration.account_id.blank?
        return connection_failure("api_token_missing", "Cloudflare認証が未設定です。") if active_configuration.api_token.blank?
        return connection_failure("project_missing", "Cloudflare Pages Projectが未設定です。") if active_configuration.project_name.blank?

        uri = URI("https://api.cloudflare.com/client/v4/accounts/#{active_configuration.account_id}/pages/projects/#{active_configuration.project_name}")
        request = Net::HTTP::Get.new(uri)
        request["Authorization"] = "Bearer #{active_configuration.api_token}"
        request["Content-Type"] = "application/json"
        response = http_adapter.call(uri, request)
        body = JSON.parse(response.body.presence || "{}")
        if response.is_a?(Net::HTTPSuccess) && body["success"] != false
          return ConnectionResult.new(
            ok: true,
            code: "ok",
            project_name: active_configuration.project_name,
            http_status: response.code.to_i,
            message: "Cloudflare Pages Projectへ接続できました。"
          )
        end

        code, message = cloudflare_connection_error(response.code.to_i, body)
        connection_failure(code, message, http_status: response.code.to_i)
      rescue JSON::ParserError
        connection_failure("invalid_response", "Cloudflare APIの応答を解析できませんでした。")
      rescue StandardError => e
        connection_failure("connection_failed", "Cloudflare接続確認に失敗しました: #{e.message}")
      end

      private

      attr_reader :configuration, :http_adapter

      def active_configuration
        @active_configuration || configuration
      end

      def cloudflare_deployment(commit_sha)
        return unless active_configuration.cloudflare_api_configured?

        uri = URI("https://api.cloudflare.com/client/v4/accounts/#{active_configuration.account_id}/pages/projects/#{active_configuration.project_name}/deployments?env=production&per_page=20")
        request = Net::HTTP::Get.new(uri)
        request["Authorization"] = "Bearer #{active_configuration.api_token}"
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

      def verify_public_page(response)
        return PageVerification.new(
          ok: false,
          title: nil,
          message: "Cloudflare Pagesの公開URL反映を待っています。HTTP #{response.code}"
        ) unless response.is_a?(Net::HTTPSuccess)

        html = response.body.to_s
        content_type = response["content-type"].to_s.downcase
        unless html.present? && (content_type.include?("html") || html.match?(%r{<!doctype\s+html|<html\b}i))
          return PageVerification.new(
            ok: false,
            title: nil,
            message: "HTTP 200ですが公開ページのHTMLを取得できませんでした。"
          )
        end

        document = Nokogiri::HTML5(html)
        title = document.at_css("title")&.text.to_s.strip
        body = document.at_css("body")&.text.to_s.squish
        if title.blank? || body.blank?
          return PageVerification.new(
            ok: false,
            title: title.presence,
            message: "HTTP 200ですが公開ページのタイトルまたは本文を取得できませんでした。"
          )
        end
        if generic_page?(title, body)
          return PageVerification.new(
            ok: false,
            title:,
            message: "Cloudflare Pagesの汎用初期ページが表示されています。実LPの反映を待っています。"
          )
        end

        PageVerification.new(ok: true, title:, message: "実LPのHTMLを確認しました。")
      rescue StandardError => e
        PageVerification.new(ok: false, title: nil, message: "公開ページのHTML確認に失敗しました: #{e.message}")
      end

      def generic_page?(title, body)
        title.casecmp("AICOO LP").zero? || body.match?(/Cloudflare Pages is ready/i)
      end

      def complete!(landing_page, deployment, url, response:, deleted:, page_title:)
        now = Time.current
        auto_register_service_url = !deleted && existing_service_url(landing_page).blank?
        generation_run = deleted ? nil : generation_run_for(landing_page)
        ga4_warning = ga4_missing_warning(generation_run)
        pipeline_stage = ga4_warning ? "completed" : "ga4_pending"
        landing_page_metadata = landing_page.metadata.to_h
        unless deleted || ga4_warning
          landing_page_metadata = landing_page_metadata.except(
            "ga4_measurement_warning",
            "ga4_measurement_warning_at",
            "publication_notice"
          )
        end
        metadata = landing_page_metadata.merge(
          "cloudflare_deploy_status" => deleted ? "deleted" : "deployed",
          "cloudflare_deployment_id" => deployment&.dig("id"),
          "cloudflare_http_status" => response.code.to_i,
          "cloudflare_content_type" => response["content-type"].presence,
          "cloudflare_page_title" => page_title,
          "cloudflare_html_verified" => !deleted,
          "cloudflare_generic_page" => false,
          "cloudflare_last_checked_at" => now.iso8601,
          "cloudflare_last_message" => deleted ? "削除確認完了" : "HTTP 200・実LP確認完了",
          "last_published_at" => now.iso8601,
          "last_sync_at" => now.iso8601,
          "sync_status" => "synced",
          "planning_status" => deleted ? "archived" : (ga4_warning ? "completed" : "measurement_pending"),
          "pipeline_stage" => deleted ? "completed" : pipeline_stage,
          "pipeline_stages" => Aicoo::LpIntegration::LandingPagePipelineState.build(
            current: deleted ? "completed" : pipeline_stage,
            approval_required: false
          )
        ).compact
        metadata["lp_public_status"] = "published" unless deleted
        if ga4_warning
          metadata.merge!(
            "ga4_measurement_warning" => ga4_warning,
            "ga4_measurement_warning_at" => now.iso8601,
            "publication_notice" => Aicoo::Lovable::StaticArtifactValidator::GA4_PUBLICATION_NOTICE
          )
        end
        if auto_register_service_url
          metadata.merge!(
            "service_url" => url,
            "service_url_auto_registered_at" => now.iso8601,
            "service_url_auto_registration_message" => "Service URLを自動登録しました",
            "cloudflare_public_url_acquired_at" => now.iso8601,
            "cloudflare_public_url_acquired_message" => "Cloudflare公開URLを取得しました"
          )
        end
        landing_page.update!(metadata:)
        stamp_generation_run!(
          generation_run,
          landing_page,
          url,
          deployment,
          response,
          page_title:,
          auto_register_service_url:,
          registered_at: now
        ) unless deleted
        Result.new(
          completed: true,
          status: deleted ? "deleted" : "deployed",
          deployment_id: deployment&.dig("id"),
          url:,
          message: deleted ? "Cloudflare PagesからLPを削除しました。" : "Cloudflare PagesでLPを公開しました。"
        )
      end

      def existing_service_url(landing_page)
        landing_page.business.business_execution_profile&.production_url.presence ||
          landing_page.business.business_services.where.not(url: [ nil, "" ]).order(:id).pick(:url) ||
          landing_page.metadata.to_h["service_url"].presence
      end

      def stamp_generation_run!(
        run,
        landing_page,
        url,
        deployment,
        response,
        page_title:,
        auto_register_service_url:,
        registered_at:
      )
        return unless run

        publication = run.metadata.to_h.fetch("publication", {}).merge(
          "status" => "published",
          "published" => true,
          "production_url" => url,
          "deploy_id" => deployment&.dig("id"),
          "http_status" => response.code.to_i,
          "content_type" => response["content-type"].presence,
          "page_title" => page_title,
          "html_verified" => true,
          "generic_page" => false,
          "published_at" => Time.current.iso8601,
          "last_synced_at" => Time.current.iso8601
        ).compact
        initial_publication_metadata = if auto_register_service_url
          {
            "service_url_auto_registration_pending" => false,
            "service_url_auto_registered_at" => registered_at.iso8601,
            "service_url_auto_registration_message" => "Service URLを自動登録しました",
            "cloudflare_public_url_acquired_at" => registered_at.iso8601,
            "cloudflare_public_url_acquired_message" => "Cloudflare公開URLを取得しました"
          }
        else
          {}
        end
        ga4_warning = ga4_missing_warning(run)
        completion_metadata = if ga4_warning
          {
            "pipeline_status" => "completed",
            "ga4_measurement_warning" => ga4_warning,
            "ga4_measurement_warning_at" => registered_at.iso8601,
            "publication_notice" => Aicoo::Lovable::StaticArtifactValidator::GA4_PUBLICATION_NOTICE
          }
        else
          {
            "pipeline_status" => "measurement_waiting",
            "measurement_started_at" => Time.current.iso8601
          }
        end
        run_metadata = run.metadata.to_h
        unless ga4_warning
          run_metadata = run_metadata.except(
            "ga4_measurement_warning",
            "ga4_measurement_warning_at",
            "publication_notice"
          )
        end
        run.update!(metadata: run_metadata.merge(
          "publication" => publication,
          "lovable_status" => "completed",
          "cloudflare_retry_count" => landing_page.metadata.to_h["cloudflare_retry_count"]
        ).merge(initial_publication_metadata).merge(completion_metadata).compact)
      end

      def generation_run_for(landing_page)
        run_id = landing_page.metadata.to_h["lovable_generation_run_id"]
        AicooLabGenerationRun.find_by(id: run_id) if run_id.present?
      end

      def ga4_missing_warning(generation_run)
        Array(generation_run&.metadata.to_h&.dig("static_validation_warnings")).find do |warning|
          warning == Aicoo::Lovable::StaticArtifactValidator::GA4_MISSING_WARNING
        end
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

      def connection_failure(code, message, http_status: nil)
        ConnectionResult.new(
          ok: false,
          code:,
          project_name: active_configuration.project_name,
          http_status:,
          message:
        )
      end

      def cloudflare_connection_error(status, body)
        return [ "api_token_invalid", "Cloudflare API Tokenが無効または期限切れです。" ] if status.in?([ 401, 403 ])
        return [ "project_not_found", "Cloudflare Pages Project #{active_configuration.project_name} が存在しません。" ] if status == 404

        message = Array(body["errors"]).filter_map { |error| error.to_h["message"].presence }.join(" / ")
        [ "connection_failed", message.presence || "Cloudflare APIへ接続できませんでした。HTTP #{status}" ]
      end

      def perform_http(uri, request)
        Net::HTTP.start(uri.hostname, uri.port, use_ssl: uri.scheme == "https", open_timeout: 10, read_timeout: 20) do |http|
          http.request(request)
        end
      end
    end
  end
end
