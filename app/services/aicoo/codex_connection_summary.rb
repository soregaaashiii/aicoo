module Aicoo
  class CodexConnectionSummary
    GlobalSettings = Data.define(
      :profile_count,
      :codex_enabled_count,
      :github_configured_count,
      :github_token_configured,
      :default_working_branch,
      :pr_rule,
      :auto_review_label,
      :auto_merge_enabled_count,
      :auto_deploy_enabled_count
    )
    BusinessRow = Data.define(
      :business,
      :profile,
      :github_repo,
      :base_branch,
      :working_branch_prefix,
      :deploy_target,
      :production_url,
      :health_check_url,
      :codex_enabled,
      :codex_ready,
      :missing_fields
    )
    TaskSummary = Data.define(
      :waiting_count,
      :submitted_count,
      :pr_created_count,
      :review_waiting_count,
      :merge_waiting_count,
      :deploy_waiting_count,
      :failed_count
    )
    Check = Data.define(:key, :label, :status, :message)
    Result = Data.define(:global_settings, :business_rows, :task_summary, :checks, :recent_submissions, :recent_tasks)

    def call
      profiles = BusinessExecutionProfile.includes(:business).order(updated_at: :desc).to_a
      business_rows = build_business_rows

      Result.new(
        global_settings: build_global_settings(profiles),
        business_rows:,
        task_summary: build_task_summary,
        checks: build_checks(profiles, business_rows),
        recent_submissions: CodexSubmission.includes(:business, :auto_revision_task, :business_execution_profile).recent.limit(8),
        recent_tasks: AutoRevisionTask.includes(:business, :codex_submission).recent.limit(8)
      )
    end

    private

    def build_global_settings(profiles)
      GlobalSettings.new(
        profile_count: profiles.size,
        codex_enabled_count: profiles.count(&:codex_enabled?),
        github_configured_count: profiles.count { |profile| profile.effective_codex_repository_url.present? },
        github_token_configured: ENV["GITHUB_TOKEN"].present? || ENV["GH_TOKEN"].present?,
        default_working_branch: most_common_branch_prefix(profiles),
        pr_rule: pr_rule_label(profiles),
        auto_review_label: "Codex Prompt確認 + PR後レビュー",
        auto_merge_enabled_count: profiles.count(&:codex_auto_merge_enabled?),
        auto_deploy_enabled_count: profiles.count(&:codex_auto_deploy_enabled?)
      )
    end

    def build_business_rows
      Business.real_businesses.includes(:business_execution_profile).order(:name).map do |business|
        profile = business.business_execution_profile
        BusinessRow.new(
          business:,
          profile:,
          github_repo: profile&.effective_codex_repository_url.presence || "-",
          base_branch: profile&.effective_codex_base_branch.presence || "-",
          working_branch_prefix: profile&.effective_codex_working_branch_prefix.presence || "-",
          deploy_target: profile&.deploy_target.presence || "-",
          production_url: profile&.production_url.presence || "-",
          health_check_url: profile&.health_check_url.presence || "-",
          codex_enabled: profile&.codex_enabled? || false,
          codex_ready: profile&.codex_ready_for_submission? || false,
          missing_fields: profile ? profile.codex_required_missing_fields : [ "Execution Profile" ]
        )
      end
    end

    def build_task_summary
      TaskSummary.new(
        waiting_count: AutoRevisionTask.where(status: %w[waiting_approval approved queued ready_for_codex]).count,
        submitted_count: CodexSubmission.where(status: "submitted").count,
        pr_created_count: CodexSubmission.where(status: %w[submitted completed]).where.not(response_payload: {}).count,
        review_waiting_count: AutoRevisionTask.where(status: %w[ready_for_codex sent_to_codex running]).count,
        merge_waiting_count: CodexSubmission.where(status: "completed").where.not(response_payload: {}).count,
        deploy_waiting_count: AutoRevisionTask.where(status: %w[completed succeeded partial_succeeded]).count,
        failed_count: AutoRevisionTask.where(status: "failed").count + CodexSubmission.where(status: "failed").count
      )
    end

    def build_checks(profiles, business_rows)
      [
        repo_check(profiles),
        branch_check(business_rows),
        prompt_check(business_rows),
        pr_tracking_check,
        deploy_check(profiles)
      ]
    end

    def repo_check(profiles)
      configured_count = profiles.count { |profile| profile.effective_codex_repository_url.present? }
      status = configured_count.positive? ? "pass" : "fail"
      Check.new(:repo, "repo設定あり", status, "#{configured_count}件のRepository設定があります。")
    end

    def branch_check(business_rows)
      enabled_rows = business_rows.select(&:codex_enabled)
      missing_count = enabled_rows.count { |row| row.base_branch == "-" || row.working_branch_prefix == "-" }
      status = if enabled_rows.empty?
        "warning"
      elsif missing_count.zero?
        "pass"
      else
        "warning"
      end
      Check.new(:branch, "branch設定あり", status, "Codex有効Business #{enabled_rows.size}件 / branch不足 #{missing_count}件")
    end

    def prompt_check(business_rows)
      ready_count = business_rows.count(&:codex_ready)
      waiting_tasks = AutoRevisionTask.where(status: %w[waiting_approval approved queued ready_for_codex]).count
      status = ready_count.positive? ? "pass" : "warning"
      Check.new(:prompt, "prompt生成可能", status, "Codex投入可能Business #{ready_count}件 / 改修待ちTask #{waiting_tasks}件")
    end

    def pr_tracking_check
      tracked_count = CodexSubmission.where(status: %w[submitted completed]).where.not(response_payload: {}).count
      status = tracked_count.positive? ? "pass" : "warning"
      Check.new(:pr_tracking, "PR追跡可能", status, "Codex送信後payload保存 #{tracked_count}件")
    end

    def deploy_check(profiles)
      configured_count = profiles.count { |profile| profile.deploy_target.present? && (profile.production_url.present? || profile.health_check_url.present? || profile.deploy_command.present?) }
      status = configured_count.positive? ? "pass" : "warning"
      Check.new(:deploy, "deploy連携あり", status, "#{configured_count}件のdeploy確認設定があります。")
    end

    def most_common_branch_prefix(profiles)
      prefixes = profiles.map(&:effective_codex_working_branch_prefix).compact_blank
      prefixes.tally.max_by { |_prefix, count| count }&.first || "aicoo/"
    end

    def pr_rule_label(profiles)
      return "Execution Profile未設定" if profiles.empty?

      auto_pr_count = profiles.count(&:codex_auto_pr_enabled?)
      "#{auto_pr_count}/#{profiles.size}件でPR作成ON。high riskは自動merge/deploy禁止。"
    end
  end
end
