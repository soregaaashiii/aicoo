require "base64"
require "cgi"
require "json"
require "net/http"
require "uri"

module Aicoo
  module CloudflarePages
    class GithubRepositoryClient
      Result = Data.define(:commit_sha, :commit_url, :changed_paths)

      def initialize(repository_url:, branch:, token:, http_adapter: nil)
        @repository_slug = normalize_repository(repository_url)
        @branch = branch.presence || "main"
        @token = token
        @http_adapter = http_adapter || method(:perform_http)
      end

      def commit!(files:, deleted_paths: [], message:)
        validate!
        ref = get("/git/ref/heads/#{escape(branch)}")
        parent_sha = ref.dig("object", "sha")
        parent = get("/git/commits/#{parent_sha}")
        base_tree_sha = parent.fetch("tree").fetch("sha")

        entries = files.map do |path, content|
          blob = post("/git/blobs", content: Base64.strict_encode64(content.to_s.b), encoding: "base64")
          { path:, mode: "100644", type: "blob", sha: blob.fetch("sha") }
        end
        entries.concat(Array(deleted_paths).map { |path| { path:, mode: "100644", type: "blob", sha: nil } })
        raise ArgumentError, "GitHubへ反映するLPファイルがありません。" if entries.empty?

        tree = post("/git/trees", base_tree: base_tree_sha, tree: entries)
        commit = post("/git/commits", message:, tree: tree.fetch("sha"), parents: [ parent_sha ])
        patch("/git/refs/heads/#{escape(branch)}", sha: commit.fetch("sha"), force: false)

        Result.new(
          commit_sha: commit.fetch("sha"),
          commit_url: commit["html_url"].presence || "https://github.com/#{repository_slug}/commit/#{commit.fetch('sha')}",
          changed_paths: entries.map { |entry| entry.fetch(:path) }
        )
      end

      def paths_under(prefix)
        validate!
        ref = get("/git/ref/heads/#{escape(branch)}")
        parent = get("/git/commits/#{ref.dig('object', 'sha')}")
        tree = get("/git/trees/#{parent.dig('tree', 'sha')}?recursive=1")
        normalized_prefix = prefix.to_s.delete_suffix("/") + "/"
        Array(tree["tree"]).filter_map do |entry|
          path = entry["path"].to_s
          path if entry["type"] == "blob" && path.start_with?(normalized_prefix)
        end
      end

      private

      attr_reader :repository_slug, :branch, :token, :http_adapter

      def validate!
        raise ArgumentError, "AICOO_GITHUB_TOKENまたはGITHUB_TOKENが未設定です。" if token.blank?
        raise ArgumentError, "LP専用GitHub Repositoryが未設定です。" if repository_slug.blank?
      end

      def get(path)
        request_json(Net::HTTP::Get, path)
      end

      def post(path, payload)
        request_json(Net::HTTP::Post, path, payload)
      end

      def patch(path, payload)
        request_json(Net::HTTP::Patch, path, payload)
      end

      def request_json(request_class, path, payload = nil)
        uri = URI("https://api.github.com/repos/#{repository_slug}#{path}")
        request = request_class.new(uri)
        request["Accept"] = "application/vnd.github+json"
        request["Authorization"] = "Bearer #{token}"
        request["X-GitHub-Api-Version"] = "2022-11-28"
        request["User-Agent"] = "aicoo-lp-publisher"
        request["Content-Type"] = "application/json"
        request.body = JSON.generate(payload) if payload
        response = http_adapter.call(uri, request)
        body = JSON.parse(response.body.presence || "{}")
        return body if response.is_a?(Net::HTTPSuccess)

        raise ArgumentError, body["message"].presence || "GitHub APIに失敗しました。HTTP #{response.code}"
      rescue JSON::ParserError
        raise ArgumentError, "GitHub APIから不正なレスポンスが返りました。"
      end

      def perform_http(uri, request)
        Net::HTTP.start(uri.hostname, uri.port, use_ssl: true, open_timeout: 10, read_timeout: 30) do |http|
          http.request(request)
        end
      end

      def normalize_repository(value)
        text = value.to_s.strip.delete_suffix(".git")
        text = text.sub(%r{\Ahttps://github\.com/}, "").sub(%r{\Agit@github\.com:}, "")
        parts = text.split(/[\/?#]/).reject(&:blank?)
        return unless parts.size >= 2

        "#{parts[0]}/#{parts[1]}"
      end

      def escape(value)
        CGI.escape(value.to_s).tr("+", "%20")
      end
    end
  end
end
