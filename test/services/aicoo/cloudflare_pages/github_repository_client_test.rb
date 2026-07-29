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

      test "explains private repository token access and retry steps in Japanese" do
        adapter = lambda do |_uri, _request|
          response(Net::HTTPNotFound, { message: "Not Found" }.to_json, code: "404", message: "Not Found")
        end
        client = GithubRepositoryClient.new(
          repository_url: "https://github.com/soregaaashiii/aicoo-lp",
          branch: "main",
          token: "token-without-repository-access",
          http_adapter: adapter
        )

        error = assert_raises(ArgumentError) { client.paths_under("public/lp/") }

        assert_includes error.message, "AICOO_GITHUB_TOKEN"
        assert_includes error.message, "Fine-grained personal access token"
        assert_includes error.message, "ContentsをRead and write"
        assert_includes error.message, "再試行"
      end

      test "reads an allowed repository snapshot without backend and environment files" do
        adapter = lambda do |uri, request|
          body = case [ request.method, uri.path ]
          when [ "GET", "/repos/example/lovable-result/git/ref/heads/main" ]
            { object: { sha: "source-commit" } }
          when [ "GET", "/repos/example/lovable-result/git/commits/source-commit" ]
            { tree: { sha: "source-tree" } }
          when [ "GET", "/repos/example/lovable-result/git/trees/source-tree" ]
            {
              tree: [
                { path: "dist/index.html", type: "blob", sha: "html", size: 20 },
                { path: ".env", type: "blob", sha: "secret", size: 20 },
                { path: "supabase/functions/index.ts", type: "blob", sha: "backend", size: 20 }
              ]
            }
          when [ "GET", "/repos/example/lovable-result/git/blobs/html" ]
            { content: Base64.strict_encode64("<title>LP</title>"), encoding: "base64" }
          else
            raise "unexpected request #{request.method} #{uri}"
          end
          response(Net::HTTPOK, body.to_json)
        end
        client = GithubRepositoryClient.new(
          repository_url: "https://github.com/example/lovable-result",
          branch: "main",
          token: nil,
          http_adapter: adapter
        )

        snapshot = client.snapshot!

        assert_equal "source-commit", snapshot.commit_sha
        assert_equal [ "dist/index.html" ], snapshot.files.keys
        assert_equal [ ".env", "supabase/functions/index.ts" ], snapshot.excluded_paths
      end

      test "reads the webhook commit instead of a newer branch head" do
        requests = []
        adapter = lambda do |uri, request|
          requests << uri.path
          body = case [ request.method, uri.path ]
          when [ "GET", "/repos/example/lovable-result/git/commits/webhook-sha" ]
            { tree: { sha: "webhook-tree" } }
          when [ "GET", "/repos/example/lovable-result/git/trees/webhook-tree" ]
            { tree: [ { path: "index.html", type: "blob", sha: "html", size: 20 } ] }
          when [ "GET", "/repos/example/lovable-result/git/blobs/html" ]
            { content: Base64.strict_encode64("<title>Webhook LP</title>"), encoding: "base64" }
          else
            raise "unexpected request #{request.method} #{uri}"
          end
          response(Net::HTTPOK, body.to_json)
        end
        client = GithubRepositoryClient.new(
          repository_url: "https://github.com/example/lovable-result",
          branch: "main",
          token: nil,
          http_adapter: adapter
        )

        snapshot = client.snapshot!(commit_sha: "webhook-sha")

        assert_equal "webhook-sha", snapshot.commit_sha
        assert_not_includes requests, "/repos/example/lovable-result/git/ref/heads/main"
      end

      private

      def response(klass, body, code: "200", message: "OK")
        klass.new("1.1", code, message).tap do |response|
          response.define_singleton_method(:body) { body }
        end
      end
    end
  end
end
