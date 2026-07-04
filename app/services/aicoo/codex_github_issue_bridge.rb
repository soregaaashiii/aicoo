require "net/http"
require "json"

module Aicoo
  class CodexGithubIssueBridge
    Result = Data.define(:created, :issue_url, :issue_number, :message, :payload)

    def initialize(codex_submission)
      @codex_submission = codex_submission
    end

    def call
      return existing_result if existing_issue_url.present?
      raise ArgumentError, "GITHUB_TOKENまたはAICOO_GITHUB_TOKENが未設定です。" if github_token.blank?
      raise ArgumentError, "GitHub repositoryが未設定です。" if repo_slug.blank?

      response = post_issue!
      body = JSON.parse(response.body.presence || "{}")

      unless response.is_a?(Net::HTTPSuccess)
        message = body["message"].presence || "GitHub Issue作成に失敗しました。HTTP #{response.code}"
        codex_submission.mark_failed!(message)
        codex_submission.update!(response_payload: codex_submission.response_payload.to_h.merge("github_issue_error" => body))
        return Result.new(created: false, issue_url: nil, issue_number: nil, message:, payload: body)
      end

      issue_url = body["html_url"]
      issue_number = body["number"]
      payload = codex_submission.response_payload.to_h.merge(
        "github_issue_url" => issue_url,
        "github_issue_number" => issue_number,
        "github_issue_api_url" => body["url"],
        "github_issue_created_at" => Time.current.iso8601,
        "github_issue_repo" => repo_slug,
        "codex_handoff_mode" => "github_issue"
      )
      codex_submission.mark_submitted!(payload:)

      Result.new(
        created: true,
        issue_url:,
        issue_number:,
        message: "GitHub Issue ##{issue_number} を作成しました。",
        payload:
      )
    end

    private

    attr_reader :codex_submission

    def existing_result
      Result.new(
        created: false,
        issue_url: existing_issue_url,
        issue_number: codex_submission.response_payload.to_h["github_issue_number"],
        message: "既にGitHub Issue作成済みです。",
        payload: codex_submission.response_payload.to_h
      )
    end

    def existing_issue_url
      codex_submission.response_payload.to_h["github_issue_url"].presence
    end

    def post_issue!
      uri = URI("https://api.github.com/repos/#{repo_slug}/issues")
      request = Net::HTTP::Post.new(uri)
      request["Accept"] = "application/vnd.github+json"
      request["Authorization"] = "Bearer #{github_token}"
      request["X-GitHub-Api-Version"] = "2022-11-28"
      request["User-Agent"] = "aicoo-codex-bridge"
      request.body = JSON.generate(issue_payload)

      Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) do |http|
        http.request(request)
      end
    end

    def issue_payload
      {
        title: issue_title,
        body: issue_body,
        labels: labels
      }.compact
    end

    def issue_title
      "[AICOO Codex] #{codex_submission.business.name}: #{codex_submission.auto_revision_task.title}".truncate(120)
    end

    def issue_body
      <<~BODY
        このIssueはAICOOの自動改修ループから作成されました。

        ## 次にやること

        1. Codex CloudでこのIssueを開く
        2. 下記プロンプトに従って作業ブランチを作る
        3. Pull Requestを作成する
        4. PR URLをAICOOのCodexSubmissionへ戻す

        ## AICOO Tracking

        - CodexSubmission ID: #{codex_submission.id}
        - AutoRevisionTask ID: #{codex_submission.auto_revision_task_id}
        - Business ID: #{codex_submission.business_id}
        - Business: #{codex_submission.business.name}
        - Base Branch: #{codex_submission.base_branch}
        - Working Branch: #{codex_submission.working_branch}

        ## Codex Prompt

        ```markdown
        #{codex_submission.prompt}
        ```
      BODY
    end

    def labels
      [
        "aicoo",
        "codex",
        "aicoo-codex",
        "auto-revision",
        "risk:#{codex_submission.auto_revision_task.risk_level}"
      ]
    end

    def repo_slug
      @repo_slug ||= normalize_repo(codex_submission.repository_url)
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
