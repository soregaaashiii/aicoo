require "test_helper"

module Aicoo
  module CloudflarePages
    class GithubRepositoryClientTest < ActiveSupport::TestCase
      test "writes all files through one tree one commit and one ref update" do
        requests = []
        adapter = lambda do |uri, request|
          requests << [ request.method, uri.path, request.body ]
          body = case [ request.method, uri.path ]
          when [ "GET", "/repos/soregaaashiii/aicoo-lp/git/ref/heads/main" ]
            { object: { sha: "parent" } }
          when [ "GET", "/repos/soregaaashiii/aicoo-lp/git/commits/parent" ]
            { tree: { sha: "base-tree" } }
          when [ "POST", "/repos/soregaaashiii/aicoo-lp/git/blobs" ]
            { sha: "blob-#{requests.count}" }
          when [ "POST", "/repos/soregaaashiii/aicoo-lp/git/trees" ]
            { sha: "new-tree" }
          when [ "POST", "/repos/soregaaashiii/aicoo-lp/git/commits" ]
            { sha: "new-commit", html_url: "https://github.com/soregaaashiii/aicoo-lp/commit/new-commit" }
          when [ "PATCH", "/repos/soregaaashiii/aicoo-lp/git/refs/heads/main" ]
            { object: { sha: "new-commit" } }
          else
            raise "unexpected request #{request.method} #{uri}"
          end
          response(Net::HTTPOK, body.to_json)
        end
        client = GithubRepositoryClient.new(
          repository_url: "https://github.com/soregaaashiii/aicoo-lp",
          branch: "main",
          token: "token",
          http_adapter: adapter
        )

        result = client.commit!(
          files: {
            "public/lp/index.html" => "<h1>LP</h1>",
            "public/lp/styles.css" => "body{}"
          },
          message: "Generate LP"
        )

        assert_equal "new-commit", result.commit_sha
        assert_equal 2, requests.count { |method, path, _body| method == "POST" && path.end_with?("/git/blobs") }
        assert_equal 1, requests.count { |method, path, _body| method == "POST" && path.end_with?("/git/trees") }
        assert_equal 1, requests.count { |method, path, _body| method == "POST" && path.end_with?("/git/commits") }
        assert_equal 1, requests.count { |method, path, _body| method == "PATCH" && path.end_with?("/git/refs/heads/main") }
      end

      private

      def response(klass, body)
        klass.new("1.1", "200", "OK").tap do |response|
          response.define_singleton_method(:body) { body }
        end
      end
    end
  end
end
