require "json"
require "net/http"
require "uri"

module Aicoo
  module CloudflarePages
    class ApiClient
      class Error < StandardError; end

      API_BASE = "https://api.cloudflare.com/client/v4".freeze
      PROJECTS_PER_PAGE = 20

      def initialize(account_id: nil, token:, http_adapter: nil)
        @account_id = account_id
        @token = token
        @http_adapter = http_adapter || method(:perform_http)
      end

      def accounts
        get("/accounts", query: { per_page: 50 })
      end

      def projects(account_id: @account_id)
        require_account!(account_id)
        path = "/accounts/#{escape(account_id)}/pages/projects"
        page = 1
        projects = []

        loop do
          payload = get_payload(path, query: { page:, per_page: PROJECTS_PER_PAGE })
          projects.concat(Array(payload["result"]))
          total_pages = payload["result_info"].to_h["total_pages"].to_i
          break if total_pages <= page

          page += 1
        end

        projects
      end

      def project(account_id: @account_id, name:)
        require_account!(account_id)
        get("/accounts/#{escape(account_id)}/pages/projects/#{escape(name)}")
      end

      def project_domains(account_id: @account_id, name:)
        require_account!(account_id)
        get("/accounts/#{escape(account_id)}/pages/projects/#{escape(name)}/domains")
      end

      def create_project(name:, production_branch: "main", source: nil, account_id: @account_id)
        require_account!(account_id)
        payload = { name:, production_branch: }
        payload[:source] = source if source.present?
        post(
          "/accounts/#{escape(account_id)}/pages/projects",
          body: payload
        )
      end

      def add_domain(name:, domain:, account_id: @account_id)
        require_account!(account_id)
        post(
          "/accounts/#{escape(account_id)}/pages/projects/#{escape(name)}/domains",
          body: { name: domain }
        )
      end

      def project_snapshots(account_id: @account_id)
        projects(account_id:).map do |project|
          project = project.to_h
          name = project["name"].to_s
          next if name.blank?

          domains = if project.key?("domains")
            Array(project["domains"]).filter_map do |domain|
              domain.is_a?(Hash) ? domain.to_h["name"].presence : domain.to_s.presence
            end
          else
            project_domains(account_id:, name:).filter_map { |domain| domain.to_h["name"].presence }
          end
          subdomain = project["subdomain"].presence || "#{name}.pages.dev"
          {
            "name" => name,
            "production_branch" => project["production_branch"].presence || "main",
            "production_url" => "https://#{subdomain}",
            "domains" => ([ subdomain ] + domains).uniq,
            "latest_deployment_id" => project.dig("latest_deployment", "id"),
            "latest_deployment_url" => project.dig("latest_deployment", "url")
          }.compact
        end.compact
      end

      private

      attr_reader :token, :http_adapter

      def get(path, query: nil)
        get_payload(path, query:)["result"]
      end

      def get_payload(path, query: nil)
        uri = uri_for(path, query:)
        request = Net::HTTP::Get.new(uri)
        perform_payload(uri, request)
      end

      def post(path, body:)
        uri = uri_for(path)
        request = Net::HTTP::Post.new(uri)
        request.body = JSON.generate(body)
        perform(uri, request)
      end

      def perform(uri, request)
        perform_payload(uri, request)["result"]
      end

      def perform_payload(uri, request)
        raise Error, "Cloudflare認証情報が未設定です。" if token.blank?

        request["Authorization"] = "Bearer #{token}"
        request["Content-Type"] = "application/json"
        response = http_adapter.call(uri, request)
        payload = JSON.parse(response.body.presence || "{}")
        unless response.is_a?(Net::HTTPSuccess) && payload["success"] != false
          message = Array(payload["errors"]).filter_map { |error| error.to_h["message"].presence }.join(" / ")
          raise Error, message.presence || "Cloudflare APIへ接続できませんでした。HTTP #{response.code}"
        end

        payload
      rescue JSON::ParserError
        raise Error, "Cloudflare APIの応答を解析できませんでした。"
      end

      def uri_for(path, query: nil)
        uri = URI("#{API_BASE}#{path}")
        uri.query = URI.encode_www_form(query) if query
        uri
      end

      def escape(value)
        URI.encode_www_form_component(value.to_s)
      end

      def require_account!(value)
        raise Error, "Cloudflare Account IDが未設定です。" if value.blank?
      end

      def perform_http(uri, request)
        Net::HTTP.start(uri.hostname, uri.port, use_ssl: true, open_timeout: 10, read_timeout: 30) do |http|
          http.request(request)
        end
      end
    end
  end
end
