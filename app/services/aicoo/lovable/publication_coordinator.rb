require "uri"

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
        landing_page_prototype = external_landing_page(business, generation_run)
        profile = business.business_execution_profile
        raise ArgumentError, "BusinessExecutionProfileが未設定です。Codex/Git/Render接続を先に設定してください。" unless profile&.active?
        if landing_page_prototype && landing_page_prototype.landing_page_repository_url.blank?
          raise ArgumentError, "LPのGitHubリポジトリを登録してください。"
        end

        candidate = find_or_create_candidate!(business, landing_page, generation_run, profile, landing_page_prototype)
        task = candidate.auto_revision_tasks.active.first || AutoRevisionTask.from_action_candidate(candidate, generated_by: "lovable_publish_button")
        raise ArgumentError, "Codex公開Taskを作成できませんでした。" unless task

        task.update!(
          target_repository_name: landing_page_prototype ? repository_name(landing_page_prototype.landing_page_repository_url) : task.target_repository_name,
          target_repository_type: landing_page_prototype ? "static_site" : task.target_repository_type,
          execution_prompt: candidate.execution_prompt,
          status: "ready_for_codex",
          risk_level: "low",
          approved_at: task.approved_at || Time.current,
          generated_by: "lovable_publish_button",
          metadata: task.metadata.to_h.merge(
            "lovable_generation_run_id" => generation_run.id,
            "lovable_project_id" => generation_run.metadata.to_h["project_id"],
            "lovable_preview_url" => generation_run.metadata.to_h["preview_url"],
            "owner_publish_approved_at" => Time.current.iso8601,
            "publication_role" => landing_page_prototype ? "codex_git_pr_cloudflare" : "codex_git_pr_merge_render"
          ).merge(external_task_metadata(landing_page_prototype))
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

      def find_or_create_candidate!(business, landing_page, run, profile, landing_page_prototype)
        existing_id = run.metadata.to_h.dig("publication", "action_candidate_id") || run.metadata.to_h["action_candidate_id"]
        existing = business.action_candidates.find_by(id: existing_id)
        file_changes = landing_page_prototype ? [ "LP専用RepositoryへLovable Previewを新しい静的LPとして反映" ] : Array(profile.target_paths).presence || [ "Lovable Previewを公開RepositoryのLP実装へ反映" ]
        completion_criteria = [
          "Lovable PreviewとDesktop/Tablet/Mobileの主要表示が一致する",
          "CTA generate_lead計測が動作する",
          "PRのCIとテストが成功する",
          landing_page_prototype ? "PR承認後にCloudflare Pagesへ公開できる状態にする" : "PRをmergeしRender deploy後にProduction URLが200を返す"
        ]
        prompt = codex_execution_prompt(business, run, profile, file_changes, completion_criteria, landing_page_prototype)
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
        }.merge(external_candidate_metadata(landing_page_prototype))
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
          title: "#{business.name} #{landing_page_prototype&.landing_page_name || 'LP'}をLovable Previewから反映して公開する",
          description: landing_page_prototype ? "Lovable #{run.metadata.to_h['version_label']}をLP専用Repositoryへ反映し、PR承認後にCloudflare Pagesへ公開する。" : "Lovable #{run.metadata.to_h['version_label']}をCodexでRepositoryへ反映し、PR・merge・Render deploy・Production確認を行う。",
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

      def codex_execution_prompt(business, run, profile, file_changes, completion_criteria, landing_page_prototype)
        repository_url = landing_page_prototype&.landing_page_repository_url || profile.effective_codex_repository_url
        branch = landing_page_prototype&.landing_page_branch || profile.effective_codex_base_branch
        deploy_target = landing_page_prototype ? "Cloudflare Pages" : "Render"
        <<~PROMPT
          #{business.name}のLPをLovable Previewから公開Repositoryへ反映してください。

          Lovable Project ID: #{run.metadata.to_h['project_id']}
          Lovable Editor: #{run.metadata.to_h['editor_url']}
          Lovable Preview: #{run.metadata.to_h['preview_url']}
          Lovable Commit: #{run.metadata.to_h['latest_commit_sha']}
          Repository: #{repository_url}
          Base Branch: #{branch}

          役割分担:
          - LovableはデザインとPreview生成済みです。
          - CodexはPreviewとLovable projectのコード・diffを確認し、公開Repositoryへ実装します。
          - Codexがbranch、commit、Pull Requestと#{deploy_target}公開準備を担当します。
          - Lovableのdeploy_projectは使用しません。
          - Service本体のRepositoryは変更しません。

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

      def external_landing_page(business, run)
        prototype_id = run.metadata.to_h["landing_page_prototype_id"]
        business.business_prototypes.active.external_landing_pages.find_by(id: prototype_id) if prototype_id.present?
      end

      def external_candidate_metadata(prototype)
        return {} unless prototype

        {
          "landing_page_id" => prototype.id,
          "campaign_id" => prototype.business_campaign_id,
          "target_repository_url" => prototype.landing_page_repository_url,
          "target_branch" => prototype.landing_page_branch,
          "target_deploy_target" => "cloudflare_pages",
          "target_url" => prototype.landing_page_url,
          "service_repository_protected" => true,
          "auto_merge" => false,
          "auto_deploy" => false
        }.compact
      end

      def external_task_metadata(prototype)
        return {} unless prototype

        external_candidate_metadata(prototype).merge(
          "landing_page_prototype_id" => prototype.id,
          "manual_approval_required" => true,
          "auto_submit_enabled" => false,
          "auto_merge_enabled" => false,
          "auto_deploy_enabled" => false
        )
      end

      def repository_name(url)
        File.basename(URI.parse(url).path, ".git")
      rescue URI::InvalidURIError
        url.to_s.split("/").last
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
