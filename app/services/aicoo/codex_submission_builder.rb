module Aicoo
  class CodexSubmissionBuilder
    Result = Data.define(:submission, :status, :ready, :reasons)

    def initialize(auto_revision_task, force: false)
      @auto_revision_task = auto_revision_task
      @force = force
    end

    def call
      return result(nil, "draft", false, [ "Execution Profileがありません。" ]) unless profile

      reasons = unavailable_reasons
      status = reasons.empty? ? "ready" : "draft"
      status = "draft" if !force && !profile.codex_auto_submit_enabled?

      submission = auto_revision_task.codex_submission || auto_revision_task.build_codex_submission
      submission.assign_attributes(
        business: auto_revision_task.business,
        business_execution_profile: profile,
        status: status,
        workspace_name: profile.codex_workspace_name,
        project_folder: profile.codex_project_folder,
        repository_url: profile.effective_codex_repository_url,
        base_branch: profile.effective_codex_base_branch,
        working_branch: auto_revision_task.codex_working_branch_name,
        prompt: prompt_body,
        error_message: reasons.join("\n").presence
      )
      submission.save!

      result(submission, status, status == "ready", reasons)
    end

    def unavailable_reasons
      return [ "Execution Profileがありません。" ] unless profile

      reasons = []
      reasons << "Codex連携がOFFです。" unless profile.codex_enabled?
      reasons.concat(profile.codex_required_missing_fields.map { |field| "#{field}が未設定です。" })
      reasons << "risk #{auto_revision_task.risk_level} がCodex Risk Limit #{profile.codex_risk_limit}を超えています。" unless profile.codex_risk_allowed?(auto_revision_task.risk_level)
      if profile.require_manual_approval? && auto_revision_task.approved_at.blank? && auto_revision_task.status.in?(%w[draft waiting_approval])
        reasons << "Owner承認が必要です。"
      end
      reasons << "Auto SubmitがOFFです。" unless force || profile.codex_auto_submit_enabled?
      reasons.compact_blank
    end

    private

    attr_reader :auto_revision_task, :force

    def profile
      @profile ||= auto_revision_task.business&.business_execution_profile&.then { |record| record.active? ? record : nil }
    end

    def prompt_body
      <<~PROMPT
        # Codex Cloud Submission

        あなたは以下の個別サービスを改修します。AICOO本体と個別サービスを混同しないでください。

        ## Service

        - Service Name: #{auto_revision_task.business.name}
        - Business ID: #{auto_revision_task.business_id}
        - Project Folder: #{profile.codex_project_folder}
        - Repository URL: #{profile.effective_codex_repository_url}
        - Base Branch: #{profile.effective_codex_base_branch}
        - Working Branch: #{auto_revision_task.codex_working_branch_name}
        - Codex Workspace: #{profile.codex_workspace_name.presence || "-"}

        ## PR / Deploy Policy

        - main直接pushは禁止
        - 作業ブランチからPRを作成してください
        - Auto PR: #{profile.codex_auto_pr_enabled? ? "可" : "不可"}
        - Auto Merge: #{profile.codex_auto_merge_enabled? ? "可" : "不可"}
        - Auto Deploy: #{profile.codex_auto_deploy_enabled? ? "可" : "不可"}
        - Risk Limit: #{profile.codex_risk_limit}
        - Task Risk: #{auto_revision_task.risk_level}
        - high riskの場合は自動merge・自動deployは禁止
        - auto_deploy_enabled=false または risk limit超過の場合はPR作成までで停止

        ## Deploy Target

        - Deploy Target: #{profile.deploy_target.presence || "-"}
        - Render Service Name: #{profile.render_service_name.presence || "-"}
        - Production URL: #{profile.production_url.presence || "-"}
        - Health Check URL: #{profile.health_check_url.presence || "-"}

        ## Estimated Target Files

        #{target_paths_prompt}

        ## Do Not

        - db:drop / db:reset / drop database は絶対に実行しない
        - 本番データを消さない
        - secrets/tokenをPR本文やログに出さない
        - 関係ない大規模リファクタリングをしない

        ## Completion Report

        完了後は以下を返してください。

        - 実装内容
        - 変更ファイル
        - 実行した確認コマンド
        - PR URL
        - merge/deployを止めた理由があれば理由
        - 残リスク

        ---

        #{auto_revision_task.codex_prompt_markdown}
      PROMPT
    end

    def target_paths_prompt
      paths = Array(profile.target_paths).presence
      return "- 未設定。対象ファイルはタスク内容から最小範囲で推定してください。" unless paths

      paths.map { |path| "- #{path}" }.join("\n")
    end

    def result(submission, status, ready, reasons)
      Result.new(submission:, status:, ready:, reasons:)
    end
  end
end
