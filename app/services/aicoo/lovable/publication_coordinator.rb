module Aicoo
  module Lovable
    class PublicationCoordinator
      Result = Data.define(:generation_run, :action_candidate, :auto_revision_task, :codex_submission, :issue_url, :message)

      def initialize(github_bridge_class: Aicoo::CodexGithubIssueBridge)
        @github_bridge_class = github_bridge_class
      end

      def call(business:, generation_run:)
        validate!(business, generation_run)
        landing_page = AicooLabLandingPage.find(generation_run.metadata.to_h.fetch("landing_page_id"))
        profile = business.business_execution_profile
        raise ArgumentError, "BusinessExecutionProfileが未設定です。Codex/Git/Render接続を先に設定してください。" unless profile&.active?

        candidate = find_or_create_candidate!(business, landing_page, generation_run, profile)
        task = candidate.auto_revision_tasks.active.first || AutoRevisionTask.from_action_candidate(candidate, generated_by: "lovable_publish_button")
        raise ArgumentError, "Codex公開Taskを作成できませんでした。" unless task

        task.update!(
          status: "ready_for_codex",
          risk_level: "low",
          approved_at: task.approved_at || Time.current,
          generated_by: "lovable_publish_button",
          metadata: task.metadata.to_h.merge(
            "lovable_generation_run_id" => generation_run.id,
            "lovable_project_id" => generation_run.metadata.to_h["project_id"],
            "lovable_preview_url" => generation_run.metadata.to_h["preview_url"],
            "owner_publish_approved_at" => Time.current.iso8601,
            "publication_role" => "codex_git_pr_merge_render"
          )
        )

        submission_result = Aicoo::CodexSubmissionBuilder.new(task, force: true).call
        unless submission_result.ready
          raise ArgumentError, "Codex公開準備が不足しています: #{submission_result.reasons.join(' / ')}"
        end

        issue_result = @github_bridge_class.new(submission_result.submission).call
        unless issue_result.issue_url.present?
          raise ArgumentError, issue_result.message
        end

        publication = generation_run.metadata.to_h.fetch("publication", {}).merge(
          "status" => "codex_submitted",
          "requested_at" => Time.current.iso8601,
          "action_candidate_id" => candidate.id,
          "auto_revision_task_id" => task.id,
          "codex_submission_id" => submission_result.submission.id,
          "github_issue_url" => issue_result.issue_url,
          "github_issue_number" => issue_result.issue_number,
          "published" => false
        )
        generation_run.update!(metadata: generation_run.metadata.to_h.merge("publication" => publication))
        landing_page.aicoo_lab_experiment.update!(approval_status: "approved")

        Result.new(
          generation_run:,
          action_candidate: candidate,
          auto_revision_task: task,
          codex_submission: submission_result.submission,
          issue_url: issue_result.issue_url,
          message: "Codex公開Taskを作成し、GitHub Issueへ送信しました。"
        )
      rescue StandardError => e
        record_failure(generation_run, e)
        raise
      end

      private

      def validate!(business, run)
        metadata = run.metadata.to_h
        raise ActiveRecord::RecordNotFound, "Lovable Versionが見つかりません。" unless metadata["pipeline"] == "lovable" && metadata["business_id"].to_i == business.id
        raise ArgumentError, "Preview生成済みVersionだけ公開できます。" unless run.status == "succeeded" && metadata["preview_url"].present?
        raise ArgumentError, "公開済みVersionです。" if metadata.dig("publication", "published") == true
      end

      def find_or_create_candidate!(business, landing_page, run, profile)
        existing_id = run.metadata.to_h.dig("publication", "action_candidate_id") || run.metadata.to_h["action_candidate_id"]
        existing = business.action_candidates.find_by(id: existing_id)
        file_changes = Array(profile.target_paths).presence || [ "Lovable Previewを公開RepositoryのLP実装へ反映" ]
        completion_criteria = [
          "Lovable PreviewとDesktop/Tablet/Mobileの主要表示が一致する",
          "CTA generate_lead計測が動作する",
          "PRのCIとテストが成功する",
          "PRをmergeしRender deploy後にProduction URLが200を返す"
        ]
        prompt = codex_execution_prompt(business, run, profile, file_changes, completion_criteria)
        execution_metadata = {
          "source_system" => "lovable",
          "generation_source_detail" => "lovable_preview",
          "lovable_generation_run_id" => run.id,
          "lovable_project_id" => run.metadata.to_h["project_id"],
          "lovable_preview_url" => run.metadata.to_h["preview_url"],
          "execution_mode" => "code_revision",
          "target_record_id" => landing_page.id,
          "target_metric" => "cvr",
          "change_content" => "Lovable Previewを公開RepositoryのLPへ忠実に実装する",
          "completion_criteria" => completion_criteria,
          "file_changes" => file_changes,
          "before" => previous_preview(run).presence || "未公開",
          "after" => run.metadata.to_h["preview_url"],
          "before_after" => [
            { "before" => previous_preview(run).presence || "未公開", "after" => run.metadata.to_h["preview_url"] }
          ],
          "auto_merge" => profile.codex_auto_merge_enabled?,
          "auto_deploy" => profile.codex_auto_deploy_enabled?,
          "publication_requires_codex" => true,
          "lovable_deploy_forbidden" => true,
          "owner_publish_approval" => true,
          "lovable_owner_preview_approved_at" => Time.current.iso8601
        }
        if existing && !existing.status.in?(ActionCandidate::INACTIVE_STATUSES)
          existing.update_columns(
            execution_prompt: prompt,
            practicality_warning: false,
            practicality_reason: nil,
            metadata: existing.metadata.to_h.merge(execution_metadata),
            updated_at: Time.current
          )
          return existing.reload
        end

        candidate = business.action_candidates.create!(
          title: "#{business.name} LPの文言とCSSをLovable Previewから反映して公開する",
          description: "Lovable #{run.metadata.to_h['version_label']}をCodexでRepositoryへ反映し、PR・merge・Render deploy・Production確認を行う。",
          action_type: "build_lp",
          generation_source: "manual",
          department: "revenue",
          status: "proposal",
          execution_prompt: prompt,
          expected_hours: 1,
          cost_yen: 0,
          immediate_value_yen: 0,
          success_probability: 0.8,
          confidence_score: 70,
          data_confidence_score: 70,
          metadata: execution_metadata
        )
        run.update!(metadata: run.metadata.to_h.merge("action_candidate_id" => candidate.id))
        candidate
      end

      def codex_execution_prompt(business, run, profile, file_changes, completion_criteria)
        <<~PROMPT
          #{business.name}のLPをLovable Previewから公開Repositoryへ反映してください。

          Lovable Project ID: #{run.metadata.to_h['project_id']}
          Lovable Editor: #{run.metadata.to_h['editor_url']}
          Lovable Preview: #{run.metadata.to_h['preview_url']}
          Lovable Commit: #{run.metadata.to_h['latest_commit_sha']}
          Repository: #{profile.effective_codex_repository_url}
          Base Branch: #{profile.effective_codex_base_branch}

          役割分担:
          - LovableはデザインとPreview生成済みです。
          - CodexはPreviewとLovable projectのコード・diffを確認し、公開Repositoryへ実装します。
          - Codexがbranch、commit、Pull Request、merge条件、Render deploy、Production確認を担当します。
          - Lovableのdeploy_projectは使用しません。

          変更対象:
          #{file_changes.map { |item| "- #{item}" }.join("\n")}

          完了条件:
          #{completion_criteria.map { |item| "- #{item}" }.join("\n")}

          禁止:
          - 期待値、円ランキング、Learning係数、Calibration係数を変更しない
          - DB migrationを追加しない
          - Previewで確認できない機能を推測で追加しない
        PROMPT
      end

      def previous_preview(run)
        previous = AicooLabGenerationRun.find_by(id: run.metadata.to_h["previous_run_id"])
        previous&.metadata.to_h&.dig("preview_url")
      end

      def record_failure(run, error)
        return unless run&.persisted?

        publication = run.metadata.to_h.fetch("publication", {}).merge(
          "status" => "failed",
          "failed_at" => Time.current.iso8601,
          "error" => error.message
        )
        run.update!(metadata: run.metadata.to_h.merge("publication" => publication))
      rescue StandardError => persistence_error
        Rails.logger.error("[Lovable] publication failure could not be persisted run_id=#{run.id}: #{persistence_error.message}")
      end
    end
  end
end
