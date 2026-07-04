#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"
require "net/http"
require "open3"
require "shellwords"
require "time"

class AicooCodexIssueWorker
  API_ROOT = "https://api.github.com"
  OPENAI_ENDPOINT = URI("https://api.openai.com/v1/responses")
  REQUIRED_LABELS = %w[aicoo-codex].freeze
  RISK_ORDER = { "low" => 1, "medium" => 2, "high" => 3 }.freeze

  Result = Struct.new(:status, :message, :pull_request_url, keyword_init: true)

  def initialize(env: ENV, stdout: $stdout)
    @env = env
    @stdout = stdout
  end

  def call
    assert_required_env!
    issue = fetch_issue
    return skip("AICOO Codex対象ラベルがありません。") unless target_issue?(issue)
    return skip("riskが自動実行上限を超えています。") unless risk_allowed?(issue)
    return skip("すでにWorker実行済みです。") if already_processed?(issue)

    comment(issue["number"], "AICOO Codex Workerを開始しました。")
    branch = working_branch(issue)
    checkout_branch(branch)
    response = generate_patch(issue)
    apply_patch(response.fetch("unified_diff"))
    run_checks(response.fetch("test_commands", []))
    commit_sha = commit_changes(response)
    pr_url = create_pull_request(issue, branch, response, commit_sha)
    notify_aicoo(issue, pr_url, commit_sha, response)
    comment(issue["number"], "AICOO Codex WorkerがPRを作成しました: #{pr_url}")

    Result.new(status: "success", message: "PRを作成しました。", pull_request_url: pr_url)
  rescue StandardError => e
    warn_message = "AICOO Codex Worker failed: #{e.class} #{e.message}"
    stdout.puts(warn_message)
    comment(issue_number, warn_message) if safe_to_comment?
    raise
  end

  private

  attr_reader :env, :stdout

  def assert_required_env!
    raise "GITHUB_TOKEN is missing." if github_token.to_s.empty?
    raise "GITHUB_REPOSITORY is missing." if repository.to_s.empty?
    raise "ISSUE_NUMBER is missing." if issue_number.to_s.empty?
    raise "OPENAI_API_KEY is missing." if openai_api_key.to_s.empty?
  end

  def fetch_issue
    get_json("/repos/#{repository}/issues/#{issue_number}")
  end

  def target_issue?(issue)
    labels = label_names(issue)
    REQUIRED_LABELS.all? { |label| labels.include?(label) } || (labels.include?("aicoo") && labels.include?("codex"))
  end

  def risk_allowed?(issue)
    issue_risk = risk_label(issue) || "low"
    RISK_ORDER.fetch(issue_risk, 99) <= RISK_ORDER.fetch(max_risk, 1)
  end

  def already_processed?(issue)
    comments = get_json("/repos/#{repository}/issues/#{issue.fetch("number")}/comments")
    comments.any? { |comment| comment["body"].to_s.include?("AICOO Codex WorkerがPRを作成しました") }
  end

  def checkout_branch(branch)
    run!("git fetch origin #{Shellwords.escape(base_branch)} --depth=1")
    run!("git checkout -B #{Shellwords.escape(branch)} origin/#{Shellwords.escape(base_branch)}")
  end

  def generate_patch(issue)
    prompt = <<~PROMPT
      You are an autonomous coding worker running inside GitHub Actions.
      Create the smallest safe code change that satisfies the GitHub Issue.

      Repository: #{repository}
      Base branch: #{base_branch}
      Working branch: #{working_branch(issue)}

      Rules:
      - Return valid JSON only.
      - Do not include secrets.
      - Do not run or suggest db:drop, db:reset, database deletion, or destructive migrations.
      - Keep the diff small and relevant.
      - If the issue is too ambiguous, change only documentation or add a failing-safe TODO file is not allowed; instead return an empty unified_diff with a clear summary.
      - unified_diff must be directly applicable by `git apply`.
      - Include tests when practical.

      Required JSON shape:
      {
        "summary": "short implementation summary",
        "commit_message": "commit message",
        "unified_diff": "git apply compatible unified diff",
        "test_commands": ["bin/rails test ..."]
      }

      GitHub Issue title:
      #{issue["title"]}

      GitHub Issue body:
      #{issue["body"]}
    PROMPT

    response = openai_response(prompt)
    parsed = JSON.parse(extract_output_text(response))
    raise "OpenAI response missing unified_diff." if parsed["unified_diff"].to_s.strip.empty?

    parsed
  rescue JSON::ParserError => e
    raise "OpenAI response was not valid JSON: #{e.message}"
  end

  def apply_patch(diff)
    patch_file = "tmp/aicoo_codex_worker.patch"
    File.write(patch_file, diff)
    run!("git apply --check #{Shellwords.escape(patch_file)}")
    run!("git apply #{Shellwords.escape(patch_file)}")
  end

  def run_checks(commands)
    selected_commands = Array(commands).map(&:to_s).reject(&:empty?)
    selected_commands = default_test_commands if selected_commands.empty?
    selected_commands.first(max_test_commands).each do |command|
      next unless allowed_check_command?(command)

      run!(command)
    end
  end

  def commit_changes(response)
    status = capture!("git status --porcelain")
    raise "OpenAI patch applied no file changes." if status.strip.empty?

    run!("git add -A")
    run!("git commit -m #{Shellwords.escape(response.fetch("commit_message", "AICOO Codex auto revision"))}")
    capture!("git rev-parse HEAD").strip
  end

  def create_pull_request(issue, branch, response, commit_sha)
    run!("git push origin #{Shellwords.escape(branch)}")
    body = <<~BODY
      This PR was created automatically by AICOO Codex Worker.

      Source Issue: ##{issue["number"]}
      Commit: #{commit_sha}

      ## Summary
      #{response["summary"]}

      ## Tests
      #{Array(response["test_commands"]).join("\n")}
    BODY

    pr_payload = {
      title: "[AICOO Codex] #{issue["title"]}".slice(0, 120),
      head: branch,
      base: base_branch,
      body:
    }
    post_json("/repos/#{repository}/pulls", pr_payload).fetch("html_url")
  end

  def notify_aicoo(issue, pr_url, commit_sha, response)
    submission_id = codex_submission_id(issue)
    return callback_skip("CodexSubmission IDがIssue本文から見つかりません。") if submission_id.to_s.empty?
    return callback_skip("AICOO_CODEX_CALLBACK_URLが未設定です。") if callback_url(submission_id).to_s.empty?
    return callback_skip("AICOO_CODEX_CALLBACK_TOKENが未設定です。") if callback_token.to_s.empty?

    uri = URI(callback_url(submission_id))
    request = Net::HTTP::Post.new(uri)
    request["Authorization"] = "Bearer #{callback_token}"
    request["Content-Type"] = "application/json"
    request.body = JSON.generate(
      pull_request_url: pr_url,
      pr_status: "pr_created",
      review_status: "pending",
      ci_status: "success",
      test_result: "success",
      merge_status: "未merge",
      deploy_status: "未deploy",
      commit_sha:,
      result_summary: response["summary"],
      changed_files: changed_files_from_commit,
      github_issue_url: issue["html_url"],
      github_issue_number: issue["number"],
      github_actions_run_id: env["GITHUB_RUN_ID"],
      github_actions_run_url: github_actions_run_url
    )

    http_response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: uri.scheme == "https") { |http| http.request(request) }
    stdout.puts("AICOO callback: #{http_response.code} #{http_response.body}")
    raise "AICOO callback failed: #{http_response.code} #{http_response.body}" unless http_response.is_a?(Net::HTTPSuccess)
  end

  def openai_response(prompt)
    request = Net::HTTP::Post.new(OPENAI_ENDPOINT)
    request["Authorization"] = "Bearer #{openai_api_key}"
    request["Content-Type"] = "application/json"
    request.body = JSON.generate(
      model: openai_model,
      input: [
        { role: "system", content: "Return only valid JSON matching the requested shape." },
        { role: "user", content: prompt }
      ],
      text: {
        format: {
          type: "json_schema",
          name: "aicoo_codex_patch",
          strict: true,
          schema: {
            type: "object",
            additionalProperties: false,
            required: %w[summary commit_message unified_diff test_commands],
            properties: {
              summary: { type: "string" },
              commit_message: { type: "string" },
              unified_diff: { type: "string" },
              test_commands: { type: "array", items: { type: "string" } }
            }
          }
        }
      }
    )

    response = Net::HTTP.start(OPENAI_ENDPOINT.hostname, OPENAI_ENDPOINT.port, use_ssl: true) { |http| http.request(request) }
    body = JSON.parse(response.body.to_s)
    return body if response.is_a?(Net::HTTPSuccess)

    raise "OpenAI API error: #{response.code} #{body["message"] || body["error"]}"
  end

  def extract_output_text(response_json)
    return response_json["output_text"] if response_json["output_text"].to_s.strip != ""

    response_json.fetch("output", []).each do |output|
      output.fetch("content", []).each do |content|
        return content["text"] if content["text"].to_s.strip != ""
      end
    end

    raise "OpenAI response did not include output text."
  end

  def allowed_check_command?(command)
    text = command.to_s.strip
    return false if text.empty?
    return false if text.match?(/\b(db:drop|db:reset|dropdb|rm\s+-rf|git\s+reset)\b/)

    allowed_prefixes.any? { |prefix| text.start_with?(prefix) }
  end

  def run!(command)
    stdout.puts("$ #{command}")
    output, status = Open3.capture2e(command)
    stdout.puts(output)
    raise "Command failed: #{command}" unless status.success?

    output
  end

  def capture!(command)
    output, status = Open3.capture2e(command)
    raise "Command failed: #{command}\n#{output}" unless status.success?

    output
  end

  def get_json(path)
    request_json(Net::HTTP::Get, path)
  end

  def post_json(path, payload)
    request_json(Net::HTTP::Post, path, payload)
  end

  def request_json(klass, path, payload = nil)
    uri = URI("#{API_ROOT}#{path}")
    request = klass.new(uri)
    request["Accept"] = "application/vnd.github+json"
    request["Authorization"] = "Bearer #{github_token}"
    request["X-GitHub-Api-Version"] = "2022-11-28"
    request["User-Agent"] = "aicoo-codex-issue-worker"
    request["Content-Type"] = "application/json" if payload
    request.body = JSON.generate(payload) if payload

    response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) { |http| http.request(request) }
    body = JSON.parse(response.body.to_s.empty? ? "{}" : response.body)
    return body if response.is_a?(Net::HTTPSuccess)

    raise "GitHub API error: #{response.code} #{body["message"] || body}"
  end

  def comment(number, body)
    post_json("/repos/#{repository}/issues/#{number}/comments", { body: })
  rescue StandardError => e
    stdout.puts("Failed to comment on issue: #{e.class} #{e.message}")
  end

  def callback_skip(message)
    stdout.puts("AICOO callback skipped: #{message}")
  end

  def codex_submission_id(issue)
    issue["body"].to_s[/CodexSubmission ID:\s*(\d+)/, 1]
  end

  def callback_url(submission_id)
    value = env["AICOO_CODEX_CALLBACK_URL"].to_s.strip
    return if value.empty?
    return value.gsub("{id}", submission_id.to_s) if value.include?("{id}")
    return "#{value.chomp("/")}/api/aicoo/codex_submissions/#{submission_id}/github_tracking" unless value.match?(%r{/api/aicoo/codex_submissions/\d+/github_tracking\z})

    value
  end

  def changed_files_from_commit
    capture!("git diff-tree --no-commit-id --name-only -r HEAD").lines.map(&:strip).reject(&:empty?)
  rescue StandardError
    []
  end

  def github_actions_run_url
    return if env["GITHUB_SERVER_URL"].to_s.empty? || env["GITHUB_REPOSITORY"].to_s.empty? || env["GITHUB_RUN_ID"].to_s.empty?

    "#{env["GITHUB_SERVER_URL"]}/#{env["GITHUB_REPOSITORY"]}/actions/runs/#{env["GITHUB_RUN_ID"]}"
  end

  def skip(message)
    stdout.puts(message)
    Result.new(status: "skipped", message:)
  end

  def safe_to_comment?
    github_token.to_s != "" && repository.to_s != "" && issue_number.to_s != ""
  end

  def label_names(issue)
    Array(issue["labels"]).filter_map do |label|
      name = label["name"].to_s.downcase
      name.empty? ? nil : name
    end
  end

  def risk_label(issue)
    label_names(issue).find { |label| label.start_with?("risk:") }&.split(":", 2)&.last
  end

  def working_branch(issue)
    "aicoo/codex-issue-#{issue.fetch("number")}"
  end

  def allowed_prefixes
    env.fetch("AICOO_CODEX_ALLOWED_CHECK_PREFIXES", "bin/rails test,bin/rails zeitwerk:check,bundle exec rubocop").split(",").map(&:strip)
  end

  def default_test_commands
    env.fetch("AICOO_CODEX_DEFAULT_TEST_COMMANDS", "bin/rails test").split(",").map(&:strip)
  end

  def max_test_commands
    env.fetch("AICOO_CODEX_MAX_TEST_COMMANDS", "2").to_i.clamp(0, 5)
  end

  def max_risk
    env.fetch("AICOO_CODEX_MAX_RISK", "low")
  end

  def base_branch
    env.fetch("AICOO_CODEX_BASE_BRANCH", "main")
  end

  def issue_number
    env["ISSUE_NUMBER"] || env["INPUT_ISSUE_NUMBER"]
  end

  def repository
    env["GITHUB_REPOSITORY"]
  end

  def github_token
    env["GITHUB_TOKEN"]
  end

  def openai_api_key
    env["OPENAI_API_KEY"]
  end

  def callback_token
    env["AICOO_CODEX_CALLBACK_TOKEN"]
  end

  def openai_model
    model = env["AICOO_CODEX_OPENAI_MODEL"].to_s.strip
    model = env["OPENAI_MODEL"].to_s.strip if model.empty?
    model.empty? ? "gpt-5.5" : model
  end
end

if $PROGRAM_NAME == __FILE__
  result = AicooCodexIssueWorker.new.call
  puts "#{result.status}: #{result.message}"
  puts result.pull_request_url if result.pull_request_url
end
