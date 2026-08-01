require "test_helper"

module Aicoo
  module CloudflarePages
    class ApiClientTest < ActiveSupport::TestCase
      test "loads pages projects and their domains with one global token and one request" do
        requests = []
        adapter = lambda do |uri, request|
          requests << [ uri.path, uri.query, request["Authorization"] ]
          response({
            success: true,
            result: [
              {
                name: "aicoo-lp",
                subdomain: "aicoo-lp.pages.dev",
                domains: [ "lp.example.com" ],
                production_branch: "main",
                latest_deployment: { id: "deploy-1", url: "https://deploy.pages.dev" }
              }
            ]
          })
        end

        projects = ApiClient.new(account_id: "account", token: "token", http_adapter: adapter).project_snapshots

        assert_equal "aicoo-lp", projects.first["name"]
        assert_equal "https://aicoo-lp.pages.dev", projects.first["production_url"]
        assert_equal %w[aicoo-lp.pages.dev lp.example.com], projects.first["domains"]
        assert requests.all? { |_path, _query, authorization| authorization == "Bearer token" }
        assert_equal "/client/v4/accounts/account/pages/projects", requests.first[0]
        assert_equal "page=1", requests.first[1]
        assert_equal 1, requests.size
      end

      test "loads all pages projects using cloudflare pagination options" do
        requests = []
        adapter = lambda do |uri, _request|
          query = URI.decode_www_form(uri.query).to_h
          requests << query
          page = query.fetch("page").to_i
          response({
            success: true,
            result: [ { name: "project-#{page}", subdomain: "project-#{page}.pages.dev", domains: [] } ],
            result_info: { page:, per_page: 10, total_pages: 2, total_count: 2 }
          })
        end

        projects = ApiClient.new(account_id: "account", token: "token", http_adapter: adapter).projects

        assert_equal %w[project-1 project-2], projects.map { |project| project["name"] }
        assert_equal [
          { "page" => "1" },
          { "page" => "2" }
        ], requests
      end

      test "loads project domains separately when the project response omits them" do
        adapter = lambda do |uri, _request|
          if uri.path.end_with?("/domains")
            response({ success: true, result: [ { name: "lp.example.com" } ] })
          else
            response({ success: true, result: [ { name: "aicoo-lp", subdomain: "aicoo-lp.pages.dev" } ] })
          end
        end

        projects = ApiClient.new(account_id: "account", token: "token", http_adapter: adapter).project_snapshots

        assert_equal %w[aicoo-lp.pages.dev lp.example.com], projects.first["domains"]
      end

      test "raises a concise error for an unsuccessful response" do
        adapter = ->(_uri, _request) { response({ success: false, errors: [ { message: "Forbidden" } ] }, status: "403") }

        error = assert_raises(ApiClient::Error) do
          ApiClient.new(account_id: "account", token: "bad", http_adapter: adapter).projects
        end

        assert_equal "Forbidden", error.message
      end

      private

      def response(body, status: "200")
        klass = status == "200" ? Net::HTTPOK : Net::HTTPForbidden
        klass.new("1.1", status, "response").tap do |result|
          result.define_singleton_method(:body) { JSON.generate(body) }
        end
      end
    end
  end
end
