require "net/http"
require "json"

module Aicoo
  class CodexGithubPrTracker
    Result = Data.define(:status, :message, :pull_request_url, :payload)

    PR_URL_PATTERN = %r{https://github\.com/([^/\s]+)/([^/\s]+)/pull/(\d+)}.freeze

    def initialize(codex_submission)
      @codex_submission = codex_submission
    end

    def call
      raise ArgumentError, "GITHUB_TOKENまたはAICOO_GITHUB_TOKENが未設定です。" if github_token.blank?
      raise ArgumentError, "GitHub Issue URLがありません。" if issue_number.blank? && codex_submission.pr_url.blank?
      raise ArgumentError, "GitHub repositoryが未設定です。" if repo_slug.blank?

      pr_url = codex_submission.pr_url.presence || detect_pull_request_url
      return Result.new(status: "waiting_pr", message: "GitHub IssueにPR URLはまだ見つかりません。", pull_request_url: nil, payload: {}) if pr_url.blank?

      pr_payload = fetch_pull_request_payload(pr_url)
      files = fetch_pull_request_files(pr_payload)
      status_payload = fetch_commit_status(pr_payload)
      tracking_payload = build_tracking_payload(pr_url, pr_payload, files, status_payload)
      codex_submission.update_tracking!(tracking_payload)

      Result.new(
        status: "synced",
        message: "GitHub PR情報を同期しました。",
        pull_request_url: pr_url,
        payload: tracking_payload.stringify_keys
      )
    end

    private

    attr_reader :codex_submission

    def detect_pull_request_url
      bodies = []
      bodies << issue_payload["body"]
      bodies.concat(issue_comments.filter_map { |comment| comment["body"] })
      bodies.join("\n").scan(PR_URL_PATTERN).map { |owner, repo, number| "https://github.com/#{owner}/#{repo}/pull/#{number}" }.first
    end

    def issue_payload
      @issue_payload ||= get_json("/repos/#{repo_slug}/issues/#{issue_number}")
    end

    def issue_comments
      @issue_comments ||= get_json("/repos/#{repo_slug}/issues/#{issue_number}/comments")
    end

    def fetch_pull_request_payload(pr_url)
      owner, repo, number = parse_pr_url(pr_url)
      get_json("/repos/#{owner}/#{repo}/pulls/#{number}")
    end

    def fetch_pull_request_files(pr_payload)
      files_url = URI(pr_payload.fetch("url")).path.sub(%r{/pulls/(\d+)\z}, '/pulls/\1/files')
      get_json(files_url).map { |file| file["filename"] }.compact_blank
    rescue KeyError
      []
    end

    def fetch_commit_status(pr_payload)
      sha = pr_payload.dig("head", "sha")
      return {} if sha.blank?

      owner, repo = pr_payload.dig("base", "repo", "full_name").to_s.split("/", 2)
      return {} if owner.blank? || repo.blank?

      get_json("/repos/#{owner}/#{repo}/commits/#{sha}/status")
    rescue StandardError => e
      Rails.logger.warn("[CodexGithubPrTracker] commit status fetch failed: #{e.class} #{e.message}")
      {}
    end

    def build_tracking_payload(pr_url, pr_payload, files, status_payload)
      {
        pull_request_url: pr_url,
        pr_status: pr_status(pr_payload),
        review_status: review_status(pr_payload),
        ci_status: status_payload["state"].presence || "未確認",
        test_result: status_payload["state"].presence,
        merge_status: merge_status(pr_payload),
        deploy_status: codex_submission.deploy_status.presence,
        tracking_updated_by: "github_sync",
        "github_pr_synced_at" => Time.current.iso8601,
        "github_pr_number" => pr_payload["number"],
        "github_pr_state" => pr_payload["state"],
        "github_pr_merged" => pr_payload["merged"],
        "github_pr_draft" => pr_payload["draft"],
        "github_pr_head_sha" => pr_payload.dig("head", "sha"),
        "changed_files" => files
      }.compact_blank
    end

    def pr_status(pr_payload)
      return "merged" if pr_payload["merged"]
      return "failed" if pr_payload["state"] == "closed"
      return "review_waiting" if pr_payload["draft"]

      "pr_created"
    end

    def review_status(pr_payload)
      return "pending" if pr_payload["draft"]
      return "approved" if pr_payload["mergeable"] == true

      "未確認"
    end

    def merge_status(pr_payload)
      return "merged" if pr_payload["merged"]
      return "failed" if pr_payload["state"] == "closed"

      "未merge"
    end

    def get_json(path)
      uri = URI("https://api.github.com#{path}")
      request = Net::HTTP::Get.new(uri)
      request["Accept"] = "application/vnd.github+json"
      request["Authorization"] = "Bearer #{github_token}"
      request["X-GitHub-Api-Version"] = "2022-11-28"
      request["User-Agent"] = "aicoo-codex-pr-tracker"

      response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) { |http| http.request(request) }
      body = JSON.parse(response.body.presence || "{}")
      return body if response.is_a?(Net::HTTPSuccess)

      raise ArgumentError, body["message"].presence || "GitHub API取得に失敗しました。HTTP #{response.code}"
    end

    def parse_pr_url(pr_url)
      match = pr_url.to_s.match(PR_URL_PATTERN)
      raise ArgumentError, "PR URLの形式が正しくありません。" unless match

      [ match[1], match[2], match[3] ]
    end

    def issue_number
      codex_submission.github_issue_number.presence || codex_submission.github_issue_url.to_s[%r{/issues/(\d+)}, 1]
    end

    def repo_slug
      codex_submission.response_payload.to_h["github_issue_repo"].presence || normalize_repo(codex_submission.repository_url)
    end

    def normalize_repo(value)
      text = value.to_s.strip
      return if text.blank?

      text = text.delete_suffix(".git")
      text = text.sub(%r{\Ahttps://github\.com/}, "")
      text = text.sub(%r{\Agit@github\.com:}, "")
      text = text.split(/[?#]/).first.to_s
      parts = text.split("/").reject(&:blank?)
      return unless parts.size >= 2

      "#{parts[0]}/#{parts[1]}"
    end

    def github_token
      ENV["AICOO_GITHUB_TOKEN"].presence || ENV["GITHUB_TOKEN"].presence
    end
  end
end
