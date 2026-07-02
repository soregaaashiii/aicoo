module Aicoo
  module CodexConnection
    class Summary
      GlobalSettings = Data.define(
        :profile_count,
        :codex_enabled_count,
        :github_configured_count,
        :github_token_configured,
        :default_base_branch,
        :default_working_branch,
        :pr_rule,
        :auto_submit_enabled_count,
        :auto_review_label,
        :auto_merge_enabled_count,
        :auto_deploy_enabled_count,
        :last_connection_checked_at,
        :last_error
      )
      BusinessRow = Data.define(
        :business,
        :profile,
        :github_repo,
        :base_branch,
        :working_branch_prefix,
        :deploy_target,
        :deploy_command,
        :test_command,
        :production_url,
        :health_check_url,
        :codex_enabled,
        :codex_ready,
        :missing_fields,
        :last_codex_run_at,
        :last_pr_url,
        :health
      )
      TaskRow = Data.define(
        :task,
        :submission,
        :business,
        :title,
        :risk,
        :priority,
        :target_repo,
        :base_branch,
        :working_branch,
        :expected_files,
        :status,
        :last_error,
        :prompt_available
      )
      PrRow = Data.define(
        :submission,
        :business,
        :pr_url,
        :github_repo,
        :branch,
        :status,
        :review_status,
        :ci_status,
        :test_result,
        :merge_status,
        :deploy_status,
        :created_at,
        :updated_at,
        :last_checked_at
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
      E2e = Data.define(:business, :health, :checks)
      OwnerSummary = Data.define(
        :waiting_count,
        :pr_waiting_count,
        :failed_count,
        :merge_waiting_count,
        :deploy_waiting_count,
        :top_task,
        :health
      )
      Result = Data.define(
        :global_settings,
        :business_rows,
        :task_rows,
        :pr_rows,
        :task_summary,
        :e2e,
        :owner_summary,
        :business_options,
        :selected_business_id
      )

      def initialize(business_id: nil)
        @selected_business_id = business_id.presence
      end

      def call
        profiles = BusinessExecutionProfile.includes(:business).order(updated_at: :desc).to_a
        business_rows = build_business_rows
        task_rows = build_task_rows
        pr_rows = build_pr_rows
        task_summary = build_task_summary(task_rows, pr_rows)

        Result.new(
          global_settings: build_global_settings(profiles),
          business_rows:,
          task_rows:,
          pr_rows:,
          task_summary:,
          e2e: build_e2e,
          owner_summary: build_owner_summary(task_summary, task_rows),
          business_options: Business.real_businesses.order(:name),
          selected_business_id: @selected_business_id
        )
      end

      private

      attr_reader :selected_business_id

      def build_global_settings(profiles)
        last_submission = CodexSubmission.order(updated_at: :desc).first
        GlobalSettings.new(
          profile_count: profiles.size,
          codex_enabled_count: profiles.count(&:codex_enabled?),
          github_configured_count: profiles.count { |profile| profile.effective_codex_repository_url.present? },
          github_token_configured: ENV["GITHUB_TOKEN"].present? || ENV["GH_TOKEN"].present?,
          default_base_branch: most_common(profiles.map(&:effective_codex_base_branch)) || "main",
          default_working_branch: most_common(profiles.map(&:effective_codex_working_branch_prefix)) || "aicoo/",
          pr_rule: pr_rule_label(profiles),
          auto_submit_enabled_count: profiles.count(&:codex_auto_submit_enabled?),
          auto_review_label: "Prompt確認 + PR後レビュー",
          auto_merge_enabled_count: profiles.count(&:codex_auto_merge_enabled?),
          auto_deploy_enabled_count: profiles.count(&:codex_auto_deploy_enabled?),
          last_connection_checked_at: last_submission&.updated_at,
          last_error: CodexSubmission.where(status: "failed").order(updated_at: :desc).pick(:error_message)
        )
      end

      def build_business_rows
        Business.real_businesses.includes(:business_execution_profile, :codex_submissions).order(:name).map do |business|
          profile = business.business_execution_profile
          last_submission = business.codex_submissions.order(updated_at: :desc).first
          missing_fields = profile ? profile.codex_required_missing_fields : [ "Execution Profile" ]
          BusinessRow.new(
            business:,
            profile:,
            github_repo: profile&.effective_codex_repository_url.presence || "-",
            base_branch: profile&.effective_codex_base_branch.presence || "-",
            working_branch_prefix: profile&.effective_codex_working_branch_prefix.presence || "-",
            deploy_target: profile&.deploy_target.presence || "-",
            deploy_command: profile&.deploy_command.presence || "-",
            test_command: profile&.test_command.presence || "-",
            production_url: profile&.production_url.presence || "-",
            health_check_url: profile&.health_check_url.presence || "-",
            codex_enabled: profile&.codex_enabled? || false,
            codex_ready: profile&.codex_ready_for_submission? || false,
            missing_fields:,
            last_codex_run_at: last_submission&.submitted_at || last_submission&.updated_at,
            last_pr_url: pr_url_for(last_submission),
            health: business_health(profile, missing_fields, last_submission)
          )
        end
      end

      def build_task_rows
        AutoRevisionTask
          .includes(:business, :codex_submission)
          .where(status: AutoRevisionTask::ACTIVE_STATUSES + %w[completed succeeded partial_succeeded failed])
          .recent
          .limit(100)
          .map { |task| build_task_row(task) }
      end

      def build_task_row(task)
        submission = task.codex_submission
        profile = task.business&.business_execution_profile
        TaskRow.new(
          task:,
          submission:,
          business: task.business,
          title: task.title,
          risk: task.risk_level,
          priority: task.priority_score,
          target_repo: submission&.repository_url.presence || profile&.effective_codex_repository_url.presence || "-",
          base_branch: submission&.base_branch.presence || profile&.effective_codex_base_branch.presence || "-",
          working_branch: submission&.working_branch.presence || task.codex_working_branch_name.presence || "-",
          expected_files: Array(profile&.target_paths).presence || [ "-" ],
          status: derived_task_status(task, submission),
          last_error: submission&.error_message.presence || task.error_message.presence || "-",
          prompt_available: submission&.prompt.present? || task.codex_prompt_markdown.present?
        )
      end

      def build_pr_rows
        CodexSubmission
          .includes(:business, :auto_revision_task)
          .where.not(response_payload: {})
          .order(updated_at: :desc)
          .limit(100)
          .filter_map do |submission|
            pr_url = pr_url_for(submission)
            next if pr_url.blank?

            payload = submission.response_payload.to_h
            PrRow.new(
              submission:,
              business: submission.business,
              pr_url:,
              github_repo: submission.repository_url,
              branch: submission.working_branch,
              status: payload["pr_status"].presence || "pr_created",
              review_status: payload["review_status"].presence || "未確認",
              ci_status: payload["ci_status"].presence || "未確認",
              test_result: payload["test_result"].presence || "未確認",
              merge_status: payload["merge_status"].presence || "未merge",
              deploy_status: payload["deploy_status"].presence || "未deploy",
              created_at: payload["pr_created_at"].presence || submission.submitted_at || submission.created_at,
              updated_at: submission.updated_at,
              last_checked_at: payload["last_checked_at"].presence || submission.updated_at
            )
          end
      end

      def build_task_summary(task_rows, pr_rows)
        TaskSummary.new(
          waiting_count: task_rows.count { |row| row.status.in?(%w[draft ready queued]) },
          submitted_count: task_rows.count { |row| row.status == "sent" },
          pr_created_count: pr_rows.size,
          review_waiting_count: pr_rows.count { |row| row.review_status.in?(%w[未確認 pending review_waiting]) },
          merge_waiting_count: pr_rows.count { |row| row.merge_status.in?(%w[未merge pending merge_waiting]) },
          deploy_waiting_count: pr_rows.count { |row| row.deploy_status.in?(%w[未deploy pending deploy_waiting]) },
          failed_count: task_rows.count { |row| row.status == "failed" }
        )
      end

      def build_e2e
        business = selected_business_id ? Business.real_businesses.find_by(id: selected_business_id) : Business.real_businesses.order(:name).first
        return E2e.new(nil, "Broken", [ Check.new(:business, "Business", "fail", "Businessがありません。") ]) unless business

        profile = business.business_execution_profile
        task_exists = business.auto_revision_tasks.exists?
        checks = [
          Check.new(:global_codex, "Codex全体ON", BusinessExecutionProfile.codex_enabled.exists? ? "pass" : "warning", "Codex有効Profile #{BusinessExecutionProfile.codex_enabled.count}件"),
          Check.new(:business_codex, "BusinessでCodex ON", profile&.codex_enabled? ? "pass" : "fail", profile ? "Profile ##{profile.id}" : "Execution Profile未作成"),
          Check.new(:repo, "GitHub repo設定あり", profile&.effective_codex_repository_url.present? ? "pass" : "fail", profile&.effective_codex_repository_url.presence || "未設定"),
          Check.new(:base_branch, "base branch設定あり", profile&.effective_codex_base_branch.present? ? "pass" : "fail", profile&.effective_codex_base_branch.presence || "未設定"),
          Check.new(:working_branch, "working branch prefix設定あり", profile&.effective_codex_working_branch_prefix.present? ? "pass" : "fail", profile&.effective_codex_working_branch_prefix.presence || "未設定"),
          Check.new(:test_command, "test command設定あり", profile&.test_command.present? ? "pass" : "warning", profile&.test_command.presence || "未設定"),
          Check.new(:health_check, "health check URL設定あり", profile&.health_check_url.present? ? "pass" : "warning", profile&.health_check_url.presence || "未設定"),
          Check.new(:task, "AutoRevisionTaskあり", task_exists ? "pass" : "warning", task_exists ? "#{business.auto_revision_tasks.count}件" : "まだありません"),
          Check.new(:prompt, "prompt生成可能", profile&.codex_ready_for_submission? ? "pass" : "fail", profile&.codex_required_missing_fields&.join(" / ").presence || "OK"),
          Check.new(:pr_tracking, "PR追跡可能", CodexSubmission.where(business:).exists? ? "pass" : "warning", "CodexSubmission #{CodexSubmission.where(business:).count}件"),
          Check.new(:deploy, "deploy設定あり", deploy_configured?(profile) ? "pass" : "warning", deploy_message(profile))
        ]
        E2e.new(business, health_for(checks), checks)
      end

      def build_owner_summary(task_summary, task_rows)
        health = if task_summary.failed_count.positive?
          "Broken"
        elsif task_summary.waiting_count.positive? || task_summary.pr_created_count.positive?
          "Warning"
        else
          "Healthy"
        end
        OwnerSummary.new(
          waiting_count: task_summary.waiting_count,
          pr_waiting_count: task_summary.pr_created_count,
          failed_count: task_summary.failed_count,
          merge_waiting_count: task_summary.merge_waiting_count,
          deploy_waiting_count: task_summary.deploy_waiting_count,
          top_task: task_rows.max_by(&:priority),
          health:
        )
      end

      def derived_task_status(task, submission)
        return "failed" if task.status == "failed" || submission&.status == "failed"
        return "completed" if task.status.in?(%w[completed succeeded partial_succeeded]) || submission&.status == "completed"
        return "deploy_waiting" if submission && tracking_value(submission, "merge_status").in?(%w[merged merge済み])
        return "merge_waiting" if submission && tracking_value(submission, "review_status").in?(%w[approved review済み])
        return "review_waiting" if submission && pr_url_for(submission).present?
        return "sent" if submission&.status == "submitted"
        return "queued" if task.status.in?(%w[queued ready_for_codex sent_to_codex running])
        return "ready" if task.status.in?(%w[approved waiting_approval])

        "draft"
      end

      def pr_url_for(submission)
        submission&.response_payload.to_h["pull_request_url"].presence || submission&.response_payload.to_h["pr_url"].presence
      end

      def tracking_value(submission, key)
        submission.response_payload.to_h[key].to_s
      end

      def business_health(profile, missing_fields, last_submission)
        return "Broken" unless profile
        return "Warning" if missing_fields.present?
        return "Broken" if last_submission&.status == "failed"

        "Healthy"
      end

      def health_for(checks)
        return "Broken" if checks.any? { |check| check.status == "fail" }
        return "Warning" if checks.any? { |check| check.status == "warning" }

        "Healthy"
      end

      def deploy_configured?(profile)
        profile && profile.deploy_target.present? && (profile.deploy_command.present? || profile.production_url.present? || profile.health_check_url.present?)
      end

      def deploy_message(profile)
        return "Execution Profile未作成" unless profile

        [
          profile.deploy_target.presence,
          profile.deploy_command.presence,
          profile.production_url.presence,
          profile.health_check_url.presence
        ].compact.join(" / ").presence || "未設定"
      end

      def most_common(values)
        values.compact_blank.tally.max_by { |_value, count| count }&.first
      end

      def pr_rule_label(profiles)
        return "Execution Profile未設定" if profiles.empty?

        auto_pr_count = profiles.count(&:codex_auto_pr_enabled?)
        "#{auto_pr_count}/#{profiles.size}件でPR作成ON。high riskは自動merge/deploy禁止。"
      end
    end
  end
end
