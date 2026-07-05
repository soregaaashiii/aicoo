class AutoRevisionTask < ApplicationRecord
  STATUSES = %w[
    draft
    waiting_approval
    approved
    queued
    ready_for_codex
    sent_to_codex
    running
    completed
    succeeded
    partial_succeeded
    failed
    canceled
  ].freeze
  RISK_LEVELS = %w[low medium high].freeze
  ACTIVE_STATUSES = %w[draft waiting_approval approved queued ready_for_codex sent_to_codex running].freeze
  CODEX_QUEUE_STATUSES = %w[queued ready_for_codex sent_to_codex running].freeze
  STALE_AFTER = 7.days

  belongs_to :action_candidate
  belongs_to :business
  belongs_to :target_business, class_name: "Business", optional: true
  has_one :codex_quality_check, dependent: :destroy
  has_one :codex_submission, dependent: :destroy
  has_many :auto_revision_executions, dependent: :destroy

  validates :title, presence: true
  validates :status, inclusion: { in: STATUSES }
  validates :risk_level, inclusion: { in: RISK_LEVELS }
  validates :priority_score, numericality: true

  scope :recent, -> { order(created_at: :desc) }
  scope :active, -> { where(status: ACTIVE_STATUSES) }
  scope :codex_queue, -> { where(status: CODEX_QUEUE_STATUSES).by_priority }
  scope :codex_check_overdue, -> {
    codex_queue.where("COALESCE(last_checked_at, sent_to_codex_at, started_running_at, created_at) < ?", STALE_AFTER.ago)
  }
  scope :stale_codex, -> {
    where(status: "running")
      .where("COALESCE(last_checked_at, started_running_at, started_at, sent_to_codex_at, created_at) < ?", STALE_AFTER.ago)
  }
  scope :by_priority, -> { order(priority_score: :desc, created_at: :desc) }

  before_validation :set_defaults
  before_validation :copy_execution_profile_defaults
  after_commit :prepare_codex_submission, on: :create

  def self.from_action_candidate(action_candidate, generated_by: "owner")
    where.not(status: "canceled").find_by(action_candidate:) ||
      create!(
        action_candidate:,
        business: action_candidate.business,
        title: action_candidate.title,
        execution_prompt: Aicoo::ExecutionPromptBuilder.new(action_candidate).call,
        priority_score: action_candidate.final_score.to_d,
        generated_by:,
        risk_level: risk_level_for(action_candidate),
        status: "waiting_approval",
        metadata: {
          "action_type" => action_candidate.action_type,
          "generation_source" => action_candidate.generation_source,
          "evaluation_reason" => action_candidate.evaluation_reason,
          "final_score" => action_candidate.final_score.to_s
        }
      )
  end

  def self.risk_level_for(action_candidate)
    text = [
      action_candidate.title,
      action_candidate.description,
      action_candidate.action_type,
      action_candidate.execution_prompt,
      action_candidate.evaluation_reason
    ].join(" ").downcase

    return "high" if text.match?(/migration|db:migrate|認証|権限|課金|売上計算|評価関数|daily run|scheduler|delete|destroy|credential|secret|token|外部api/)
    return "low" if text.match?(/文言|seoタイトル|meta description|記事追加|内部リンク|css|表示文言|タイトル改善|メタディスクリプション/)

    "medium"
  end

  def approve!
    update!(status: high_risk? ? "approved" : "ready_for_codex", approved_at: approved_at || Time.current)
  end

  def enqueue_for_codex!(operator: "owner")
    if high_risk?
      errors.add(:base, "high riskの改修は自動実行キューへ追加できません。Codex用プロンプト確認までにしてください。")
      raise ActiveRecord::RecordInvalid, self
    end

    validation = codex_prompt_target_validation
    if validation.invalid?
      errors.add(:base, validation.errors.to_sentence)
      raise ActiveRecord::RecordInvalid, self
    end

    update!(status: "queued", approved_at: approved_at || Time.current)
    auto_revision_executions.create!(
      status: "queued",
      prompt_snapshot: codex_prompt_markdown,
      metadata: execution_metadata(operator:)
    )
  end

  def mark_sent_to_codex!
    validation = codex_prompt_target_validation
    if validation.invalid?
      errors.add(:base, validation.errors.to_sentence)
      raise ActiveRecord::RecordInvalid, self
    end

    update!(status: "sent_to_codex", sent_to_codex_at: sent_to_codex_at || Time.current)
    current_execution.update!(status: "sent_to_codex", prompt_snapshot: codex_prompt_markdown)
  end

  def start_implementation!
    started_time = Time.current
    update!(
      status: "running",
      started_at: started_at || started_time,
      started_running_at: started_running_at || started_time
    )
    current_execution.update!(
      status: "running",
      started_at: current_execution.started_at || started_time,
      prompt_snapshot: current_execution.prompt_snapshot.presence || codex_prompt_markdown
    )
  end

  def stale_codex_task?
    return false unless status == "running"

    last_codex_activity_at < STALE_AFTER.ago
  end

  def last_codex_activity_at
    last_checked_at || started_running_at || started_at || sent_to_codex_at || created_at
  end

  def record_result!(attributes)
    normalized_attributes = attributes.to_h.symbolize_keys
    normalized_status = normalized_attributes[:status].presence || status
    update!(
      status: normalized_status,
      result_summary: normalized_attributes[:result_summary],
      error_message: normalized_attributes[:error_message],
      changed_files: normalized_attributes[:changed_files],
      test_result: normalized_attributes[:test_result],
      codex_output: normalized_attributes[:codex_output],
      finished_at: normalized_attributes[:finished_at].presence || Time.current
    )
    record_execution_result!(normalized_attributes.merge(status: normalized_status))
    record_new_lp_auto_deploy_result!(normalized_attributes.merge(status: normalized_status))
    run_codex_quality_check!
  end

  def create_action_execution_log!
    action_candidate.action_execution_logs.create!(
      business:,
      planned_action: title.presence || execution_prompt,
      actual_action: result_summary.presence || status,
      status: action_execution_log_status,
      started_at: started_at || created_at,
      finished_at: finished_at || Time.current,
      variance_reason: error_message,
      human_note: "AutoRevisionTask ##{id} の実装結果から作成",
      metadata: {
        "auto_revision_task_id" => id,
        "auto_revision_status" => status,
        "changed_files" => changed_files,
        "test_result" => test_result,
        "codex_quality_check_id" => codex_quality_check&.id,
        "codex_quality_result" => codex_quality_check&.result,
        "codex_quality_approval_status" => codex_quality_check&.approval_status,
        "quality_review_required" => codex_quality_check&.approval_status != "approved",
        "learning_loop_verified" => codex_quality_check&.learning_loop_verified? || false
      }
    )
  end

  def run_codex_quality_check!
    AicooCodexQualityCheckService.new(self).call
  end

  def create_or_update_codex_quality_check!(attributes)
    if codex_quality_check
      codex_quality_check.update!(attributes)
      codex_quality_check
    else
      create_codex_quality_check!(attributes)
    end
  end

  def successful_result?
    %w[completed succeeded partial_succeeded].include?(status)
  end

  def high_risk?
    risk_level == "high"
  end

  def codex_prompt
    Aicoo::CodexPromptComposer.call(business:, request_body: base_codex_prompt)
  end

  def base_codex_prompt
    <<~PROMPT
      目的:
      #{title}

      背景:
      AICOOが生成したActionCandidateを、Codexへ渡せる実行単位として整理したAutoRevisionTaskです。
      タスクID: AutoRevisionTask ##{id}
      対象事業: #{business.name}
      対象リポジトリ: #{target_repository_display}
      リポジトリ種別: #{target_repository_type.presence || "-"}
      GitHub Repository: #{execution_profile&.github_repository.presence || "-"}
      Codex Workspace: #{execution_profile&.codex_workspace_name.presence || "-"}
      Codex Project Folder: #{execution_profile&.codex_project_folder.presence || "-"}
      Codex Repository URL: #{execution_profile&.effective_codex_repository_url.presence || "-"}
      Codex Base Branch: #{execution_profile&.effective_codex_base_branch.presence || "main"}
      Codex Working Branch: #{codex_working_branch_name}
      Codex Auto Submit Enabled: #{execution_profile&.codex_auto_submit_enabled? ? "true" : "false"}
      Codex Auto PR Enabled: #{execution_profile&.codex_auto_pr_enabled? ? "true" : "false"}
      Codex Auto Merge Enabled: #{execution_profile&.codex_auto_merge_enabled? ? "true" : "false"}
      Codex Auto Deploy Enabled: #{execution_profile&.codex_auto_deploy_enabled? ? "true" : "false"}
      Codex Risk Limit: #{execution_profile&.codex_risk_limit.presence || "low"}
      Repository Path: #{execution_profile&.repository_path.presence || "-"}
      Default Branch: #{execution_profile&.default_branch.presence || "-"}
      Working Branch: #{working_branch_name}
      Commit Message: #{suggested_commit_message}
      Deploy Target: #{execution_profile&.deploy_target.presence || "-"}
      Render Service: #{execution_profile&.render_service_name.presence || "-"}
      Auto Merge Enabled: #{execution_profile&.auto_merge_enabled? ? "true" : "false"}
      Auto Deploy Enabled: #{execution_profile&.auto_deploy_enabled? ? "true" : "false"}
      Auto Deploy Risk Limit: #{execution_profile&.auto_deploy_risk_limit.presence || "low"}
      Require Manual Approval: #{execution_profile&.require_manual_approval? ? "true" : "false"}
      PR/Deploy Flow: #{execution_profile ? execution_profile.deploy_flow_label_for(self) : "Execution Profile未設定のためPR作成まで"}
      Deploy Verification URL: #{execution_profile&.production_url.presence || "-"}
      Health Check URL: #{execution_profile&.health_check_url.presence || "-"}
      action_type: #{metadata.to_h["action_type"].presence || action_candidate.action_type}
      risk_level: #{risk_level}
      rollback方針: 変更前commitを控え、異常時はAICOOにRollback依頼を記録する

      事業別Codex指示:
      #{execution_profile&.codex_instructions.presence || "特記事項はありません。"}

      実装要件:
      #{execution_prompt.presence || "ActionCandidate詳細を確認し、目的に沿って必要最小限の改修を行ってください。"}

      壊してはいけない既存機能:
      - 既存のAICOO Dashboard / Owner Dashboard
      - ActionCandidate / ActionResult / RevenueEvent / Learning Loop
      - Revenue計算式
      - Lab目的関数
      - Daily Run / Schedulerの既存挙動

      禁止事項:
      - db:drop / db:reset / drop database は絶対に実行しない
      - 既存機能を壊さない
      - 本番secretやtokenを表示しない
      - 高リスク変更は勝手に広げない
      #{profile_forbidden_pattern_prompt}

      確認コマンド:
      #{confirmation_command_prompt}
      #{migration_confirmation_commands}

      GitHub / PR / Deploy:
      - base_branch: #{execution_profile&.default_branch.presence || "main"}
      - working_branch: #{working_branch_name}
      - commit_message: #{suggested_commit_message}
      - main直接push禁止。必ず作業ブランチからPRを作成する
      - high riskの場合は自動merge・自動デプロイ禁止
      - auto_deploy_enabled=false の場合はPR作成までで停止
      - auto_deploy_enabled=true でもrisk limitを超える場合はPR作成までで停止
      - auto_merge_enabled=false の場合はPR作成までで停止
      - deploy_target: #{execution_profile&.deploy_target.presence || "-"}
      - render_service_name: #{execution_profile&.render_service_name.presence || "-"}
      - deploy確認URL: #{execution_profile&.production_url.presence || "-"}
      - health_check_url: #{execution_profile&.health_check_url.presence || "-"}

      完了報告に含めるもの:
      - 実装内容
      - 変更ファイル一覧
      - 実行した確認コマンド
      - 残リスク

      実装完了後:
      - AICOOのAutoRevisionTask ##{id} に結果を登録してください
      - changed_files に変更ファイルを記録してください
      - test_result に確認コマンドの結果を記録してください
    PROMPT
  end

  def execution_profile
    profile = business&.business_execution_profile
    return unless profile&.active?

    profile
  end

  def target_repository_display
    target_repository_name.presence || execution_profile&.display_repository_name || "-"
  end

  def repository_target_status
    profile = business&.business_execution_profile
    return "missing" unless profile

    profile.coverage_status
  end

  def repository_target_status_label
    AicooRepositoryTargetCoverageService::STATUS_LABELS.fetch(repository_target_status)
  end

  def repository_target_warning?
    repository_target_status != "configured"
  end

  def repository_target_missing_fields_label
    profile = business&.business_execution_profile
    return "Execution Profile未作成" unless profile
    return "無効化されています" if profile.coverage_status == "inactive"
    return "-" if profile.missing_required_fields.empty?

    profile.missing_required_fields.join(", ")
  end

  def codex_prompt_target_validation
    AicooCodexPromptTargetValidationService.new(self).call
  end

  def codex_prompt_markdown
    profile = execution_profile
    base_markdown = <<~MARKDOWN
      # AutoRevisionTask ##{id}: #{title}

      ## Target

      - AutoRevisionTask ID: #{id}
      - Title: #{title}
      - Business: #{business.name}
      - Target Repository Name: #{target_repository_name.presence || "-"}
      - Target Repository Type: #{target_repository_type.presence || "-"}
      - GitHub Repository: #{profile&.github_repository.presence || "-"}
      - Codex Workspace: #{profile&.codex_workspace_name.presence || "-"}
      - Codex Project Folder: #{profile&.codex_project_folder.presence || "-"}
      - Codex Repository URL: #{profile&.effective_codex_repository_url.presence || "-"}
      - Codex Base Branch: #{profile&.effective_codex_base_branch.presence || "main"}
      - Codex Working Branch: #{codex_working_branch_name}
      - Codex Auto Submit Enabled: #{profile&.codex_auto_submit_enabled? ? "true" : "false"}
      - Codex Auto PR Enabled: #{profile&.codex_auto_pr_enabled? ? "true" : "false"}
      - Codex Auto Merge Enabled: #{profile&.codex_auto_merge_enabled? ? "true" : "false"}
      - Codex Auto Deploy Enabled: #{profile&.codex_auto_deploy_enabled? ? "true" : "false"}
      - Codex Risk Limit: #{profile&.codex_risk_limit.presence || "low"}
      - Repository Path: #{profile&.repository_path.presence || "-"}
      - Default Branch: #{profile&.default_branch.presence || "-"}
      - Working Branch: #{working_branch_name}
      - Commit Message: #{suggested_commit_message}
      - Deploy Target: #{profile&.deploy_target.presence || "-"}
      - Render Service: #{profile&.render_service_name.presence || "-"}
      - Deploy Verification URL: #{profile&.production_url.presence || "-"}
      - Health Check URL: #{profile&.health_check_url.presence || "-"}
      - Auto Deploy Enabled: #{profile&.auto_deploy_enabled? ? "true" : "false"}
      - Auto Merge Enabled: #{profile&.auto_merge_enabled? ? "true" : "false"}
      - Auto Deploy Risk Limit: #{profile&.auto_deploy_risk_limit.presence || "low"}
      - Require Manual Approval: #{profile&.require_manual_approval? ? "true" : "false"}
      - PR/Deploy Flow: #{profile ? profile.deploy_flow_label_for(self) : "Execution Profile未設定のためPR作成まで"}
      - Rollback Policy: 変更前commitを控え、異常時はRollback依頼をAICOOに記録する
      - Risk Level: #{risk_level}
      - Priority Score: #{priority_score}

      ## Execution Prompt

      #{execution_prompt.presence || "ActionCandidate詳細を確認し、目的に沿って必要最小限の改修を行ってください。"}

      ## Business Codex Instructions

      #{profile&.codex_instructions.presence || "特記事項はありません。"}

      ## Repository Commands

      - Test Command: #{profile&.test_command.presence || "bin/rails test"}
      - Lint Command: #{profile&.lint_command.presence || "RUBOCOP_CACHE_ROOT=tmp/rubocop_cache bundle exec rubocop"}
      - Deploy Command: #{profile&.deploy_command.presence || "-"}

      ## GitHub / PR / Deploy Flow

      - Base Branch: #{profile&.default_branch.presence || "main"}
      - Working Branch: #{working_branch_name}
      - Commit Message: #{suggested_commit_message}
      - Pull Request: main直接push禁止。必ず作業ブランチからPRを作成する
      - high riskの場合は自動merge・自動デプロイ禁止
      - auto_deploy_enabled=false の場合はPR作成までで停止
      - auto_deploy_enabled=true でもrisk limitを超える場合はPR作成までで停止
      - auto_merge_enabled=false の場合はPR作成までで停止
      - Deploy Target: #{profile&.deploy_target.presence || "-"}
      - Render Service: #{profile&.render_service_name.presence || "-"}
      - Deploy Verification URL: #{profile&.production_url.presence || "-"}
      - Health Check URL: #{profile&.health_check_url.presence || "-"}
      - Rollback: deploy後に異常があれば変更commitを控えてRollback可能にする

      ## Forbidden Patterns

      #{markdown_list(profile&.forbidden_pattern_lines.presence || BusinessExecutionProfile::DEFAULT_FORBIDDEN_PATTERNS)}

      ## Safety Rules

      - db:drop / db:reset / drop database は絶対に実行しない
      - 既存機能を壊さない
      - 本番secretやtokenを表示しない
      - 高リスク変更は勝手に広げない

      ## Confirmation Commands

      #{confirmation_command_prompt}
      #{migration_confirmation_commands}

      ## AICOO Result Intake Template

      ```text
      AICOO Result Intake Template

      AutoRevisionTask ID:
      #{id}

      Status:
      - succeeded
      - partial_succeeded
      - failed
      - canceled

      Result Summary:

      Changed Files:

      Test Result:

      Codex Output:

      Error Message:
      ```
    MARKDOWN
    Aicoo::CodexPromptComposer.call(business:, request_body: base_markdown)
  end

  def codex_prompt_export_filename
    "auto_revision_task_#{id}_codex_prompt.md"
  end

  def record_codex_prompt_export!
    current_metadata = metadata.to_h
    export_count = current_metadata["export_count"].to_i + 1
    update!(
      metadata: current_metadata.merge(
        "last_exported_at" => Time.current.iso8601,
        "export_count" => export_count
      )
    )
  end

  private

  def set_defaults
    self.status = "draft" if status.blank?
    self.risk_level = "medium" if risk_level.blank?
    self.priority_score = 0 if priority_score.blank?
    self.generated_by = "aicoo" if generated_by.blank?
    self.metadata = {} if metadata.blank?
  end

  def copy_execution_profile_defaults
    self.target_business_id ||= business_id
    self.target_repository_name ||= business&.codex_repository_name || execution_profile&.repository_name
    self.target_repository_type ||= if business&.aicoo_internal_codex?
      "rails"
    else
      execution_profile&.repository_type
    end
  end

  def profile_forbidden_pattern_prompt
    patterns = execution_profile&.forbidden_pattern_lines || []
    return "" if patterns.empty?

    patterns.map { |pattern| "- #{pattern}" }.join("\n")
  end

  def confirmation_command_prompt
    commands = [
      execution_profile&.test_command.presence || "bin/rails test",
      "bin/rails zeitwerk:check",
      execution_profile&.lint_command.presence || "RUBOCOP_CACHE_ROOT=tmp/rubocop_cache bundle exec rubocop"
    ].uniq

    commands.map { |command| "- #{command}" }.join("\n")
  end

  def markdown_list(items)
    Array(items).map { |item| "- #{item}" }.join("\n")
  end

  def migration_confirmation_commands
    return "" unless risk_level == "high" || execution_prompt.to_s.downcase.include?("migration")

    <<~COMMANDS

      migrationが必要な場合:
      - bin/rails db:migrate
      - RAILS_ENV=test bin/rails db:migrate
    COMMANDS
  end

  def action_execution_log_status
    case status
    when "completed"
      "completed"
    when "succeeded"
      "completed"
    when "partial_succeeded"
      "partial"
    when "failed"
      "failed"
    when "canceled"
      "skipped"
    else
      "changed"
    end
  end

  def prepare_codex_submission
    Aicoo::CodexSubmissionBuilder.new(self).call
  rescue StandardError => e
    Rails.logger.warn("[CodexSubmissionBuilder] AutoRevisionTask##{id} failed: #{e.class} #{e.message}")
  end

  public

  def current_execution
    auto_revision_executions.active.recent.first ||
      auto_revision_executions.create!(
        status: status == "running" ? "running" : "queued",
        started_at: started_running_at,
        prompt_snapshot: codex_prompt_markdown,
        metadata: execution_metadata(operator: "system")
      )
  end

  def suggested_commit_message
    "Auto revision task ##{id}: #{title}".truncate(72, omission: "")
  end

  def working_branch_name
    execution_profile&.working_branch_for(self) || "codex/auto-revision-#{id}"
  end

  def codex_working_branch_name
    task_slug = title.to_s.parameterize.presence || "task"
    business_key = business&.then { |record| record.respond_to?(:slug) ? record.slug.presence : nil } || business_id
    execution_profile&.codex_working_branch_for(self) ||
      "aicoo/#{business_key}/#{id}-#{task_slug.truncate(40, omission: '')}"
  end

  def auto_deploy_allowed?
    execution_profile&.auto_deploy_allowed_for?(self) || false
  end

  def auto_merge_allowed?
    execution_profile&.auto_merge_allowed_for?(self) || false
  end

  def deploy_flow_label
    execution_profile&.deploy_flow_label_for(self) || "Execution Profile未設定のためPR作成まで"
  end

  def execution_metadata(operator:)
    profile = execution_profile
    {
      operator:,
      business_id: business_id,
      risk_level: risk_level,
      github_repository: profile&.github_repository,
      base_branch: profile&.default_branch || "main",
      working_branch: working_branch_name,
      deploy_target: profile&.deploy_target,
      render_service_name: profile&.render_service_name,
      deploy_url: profile&.production_url,
      health_check_url: profile&.health_check_url,
      auto_deploy_enabled: profile&.auto_deploy_enabled? || false,
      auto_merge_enabled: profile&.auto_merge_enabled? || false,
      codex_submission_id: codex_submission&.id,
      codex_workspace_name: profile&.codex_workspace_name,
      codex_project_folder: profile&.codex_project_folder,
      codex_repository_url: profile&.effective_codex_repository_url,
      codex_base_branch: profile&.effective_codex_base_branch,
      codex_working_branch: codex_working_branch_name,
      codex_auto_submit_enabled: profile&.codex_auto_submit_enabled? || false,
      codex_auto_pr_enabled: profile&.codex_auto_pr_enabled? || false,
      codex_auto_merge_enabled: profile&.codex_auto_merge_enabled? || false,
      codex_auto_deploy_enabled: profile&.codex_auto_deploy_enabled? || false,
      codex_risk_limit: profile&.codex_risk_limit,
      auto_deploy_allowed: auto_deploy_allowed?,
      auto_merge_allowed: auto_merge_allowed?,
      auto_deploy_risk_limit: profile&.auto_deploy_risk_limit,
      require_manual_approval: profile&.require_manual_approval? || false,
      deploy_flow: profile&.deploy_flow_for(self),
      commit_message: suggested_commit_message,
      rollback_policy: "変更前commitを控え、異常時はRollback依頼をAICOOに記録する"
    }
  end

  def record_execution_result!(attributes)
    execution_status =
      case attributes[:status].to_s
      when "completed", "succeeded", "partial_succeeded"
        "completed"
      when "failed"
        "failed"
      when "canceled"
        "canceled"
      else
        "running"
      end
    current_execution.finish!(
      status: execution_status,
      result_summary: attributes[:result_summary],
      error_message: attributes[:error_message],
      commit_sha: attributes[:commit_sha],
      pull_request_url: attributes[:pull_request_url],
      deploy_url: attributes[:deploy_url],
      deploy_status: attributes[:deploy_status]
    )
  end

  def record_new_lp_auto_deploy_result!(attributes)
    auto_build_task = AutoBuildTask.find_by(auto_revision_task: self)
    policy = Aicoo::NewLpAutoDeployPolicy.new(self)
    deploy_status_value = attributes[:deploy_status].to_s
    normalized_status = attributes[:status].to_s

    if deploy_status_value == "deployed"
      policy.record_history!(
        event: "deploy_succeeded",
        success: true,
        auto_build_task:,
        metadata: {
          "result_summary" => attributes[:result_summary],
          "deploy_url" => attributes[:deploy_url],
          "commit_sha" => attributes[:commit_sha]
        }
      )
    elsif deploy_status_value == "failed" || normalized_status == "failed"
      reason = attributes[:error_message].presence || "auto_revision_failed"
      policy.record_history!(
        event: "deploy_failed",
        success: false,
        auto_build_task:,
        metadata: {
          "reason" => reason,
          "result_summary" => attributes[:result_summary],
          "deploy_status" => deploy_status_value
        }
      )
      policy.suspend!(
        reason:,
        auto_build_task:,
        metadata: {
          "auto_revision_task_status" => normalized_status,
          "deploy_status" => deploy_status_value
        }
      )
    end
  end
end
