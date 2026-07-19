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
  before_validation :normalize_owner_approval_gate
  after_commit :prepare_codex_submission, on: :create

  def self.from_action_candidate(action_candidate, generated_by: "owner")
    if Aicoo::ArticleOpportunityCodexGate.article_opportunity_candidate?(action_candidate)
      return from_article_opportunity_candidate(action_candidate, generated_by:)
    end

    return nil unless action_candidate.code_revision_execution_mode?

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

  def self.from_article_opportunity_candidate(action_candidate, generated_by: "owner")
    gate = Aicoo::ArticleOpportunityCodexGate.call(action_candidate)
    unless gate.eligible?
      action_candidate.update_columns(
        metadata: action_candidate.metadata.to_h.merge(
          "codex_block_reason" => gate.reasons,
          "article_opportunity_codex_gate" => gate.metadata["article_opportunity_codex_gate"]
        ),
        updated_at: Time.current
      )
      return nil
    end

    existing = where(status: ACTIVE_STATUSES).find_by(action_candidate:)
    return existing if existing

    execution_prompt = Aicoo::ArticleOpportunityCodexPromptBuilder.call(action_candidate:, gate:)
    brief = action_candidate.metadata.to_h["execution_brief"].to_h
    create!(
      action_candidate:,
      business: action_candidate.business,
      title: action_candidate.title,
      execution_prompt:,
      priority_score: action_candidate.final_score.to_d,
      generated_by:,
      risk_level: gate.risk_level,
      status: "waiting_approval",
      metadata: {
        "action_type" => action_candidate.action_type,
        "generation_source" => action_candidate.generation_source,
        "value_model_name" => action_candidate.metadata.to_h["value_model_name"],
        "analysis_source" => action_candidate.metadata.to_h["analysis_source"],
        "opportunity_type" => action_candidate.metadata.to_h["opportunity_type"],
        "article_id" => action_candidate.metadata.to_h["article_id"],
        "article_path" => action_candidate.metadata.to_h["article_path"],
        "target_url" => brief.dig("target", "target_url"),
        "snapshot_id" => action_candidate.metadata.to_h["snapshot_id"],
        "execution_brief" => brief,
        "completion_conditions" => brief["completion_conditions"],
        "risk_level" => gate.risk_level,
        "codex_eligible" => true,
        "expected_improvement_score" => action_candidate.metadata.to_h["expected_improvement_score"],
        "rollback_conditions" => {
          "rollback_possible" => brief.dig("execution", "rollback_possible"),
          "prohibited_actions" => brief.dig("safety", "prohibited_actions")
        },
        "article_opportunity_codex_gate" => gate.metadata["article_opportunity_codex_gate"],
        "auto_merge_enabled" => false,
        "auto_deploy_enabled" => false,
        "deploy_disabled_reason" => "article_opportunity_codex_connection_only"
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
    unless Aicoo::ActionCandidateExecutionReadiness.call(action_candidate).ready?
      update!(
        status: "waiting_approval",
        metadata: metadata.to_h.merge(
          "approval_required_reason" => "対象や実行条件が未確定のためCodex準備へ進めません。",
          "execution_readiness" => Aicoo::ActionCandidateExecutionReadiness.call(action_candidate).metadata
        )
      )
      return false
    end

    update!(status: high_risk? ? "approved" : "ready_for_codex", approved_at: approved_at || Time.current)
  end

  def enqueue_for_codex!(operator: "owner")
    readiness = Aicoo::ActionCandidateExecutionReadiness.call(action_candidate)
    unless readiness.ready?
      errors.add(:base, "execution_readiness=#{readiness.readiness}: 対象や実行条件が未確定のためCodexへ送れません。")
      raise ActiveRecord::RecordInvalid, self
    end

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
    readiness = Aicoo::ActionCandidateExecutionReadiness.call(action_candidate)
    unless readiness.ready?
      errors.add(:base, "execution_readiness=#{readiness.readiness}: 対象や実行条件が未確定のためCodexへ送れません。")
      raise ActiveRecord::RecordInvalid, self
    end

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

  def approval_required_reason
    metadata.to_h["approval_required_reason"].presence ||
      metadata.to_h.dig("owner_approval", "reason").presence
  end

  def owner_approval_required?
    status.in?(%w[draft waiting_approval approved]) && approval_required_reason.present?
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

  def normalize_owner_approval_gate
    return unless status.in?(%w[waiting_approval approved])

    current_metadata = metadata.to_h
    reason = current_metadata["approval_required_reason"].presence ||
      current_metadata.dig("owner_approval", "reason").presence ||
      inferred_owner_approval_reason

    if reason.present?
      self.metadata = current_metadata.merge(
        "approval_required_reason" => reason,
        "owner_approval" => current_metadata["owner_approval"].to_h.merge(
          "required" => true,
          "reason" => reason,
          "reason_code" => owner_approval_reason_code(reason),
          "recorded_at" => current_metadata.dig("owner_approval", "recorded_at").presence || Time.current.iso8601
        )
      )
      return
    end

    self.status = "ready_for_codex"
    self.approved_at ||= Time.current
    self.metadata = current_metadata.merge(
      "owner_approval" => current_metadata["owner_approval"].to_h.merge(
        "required" => false,
        "reason" => nil,
        "auto_released_reason" => "承認が必要な理由がないため自動でCodex準備へ進めました。",
        "auto_released_at" => Time.current.iso8601
      )
    )
  end

  def inferred_owner_approval_reason
    text = owner_approval_signal_text

    return "本番破壊的変更の可能性があるためOwner判断が必要です。" if text.match?(/db:drop|db:reset|drop database|destroy_all|delete_all|破壊/)
    return "新しいお金または既存予算超過が発生する可能性があるためOwner判断が必要です。" if text.match?(/課金|広告費|予算|支払い|費用|cost|billing/)
    return "法的リスクまたは規約リスクがあるためOwner判断が必要です。" if text.match?(/法務|法律|規約|legal|privacy|個人情報/)
    return "ブランド変更を含む可能性があるためOwner判断が必要です。" if text.match?(/ブランド|brand|サービス名|ロゴ/)
    return "サービス方針変更を含む可能性があるためOwner判断が必要です。" if text.match?(/方針|pivot|価格変更|料金変更|撤退|統合/)
    return "高リスク改修のためOwner判断が必要です。" if high_risk?

    nil
  end

  def owner_approval_signal_text
    [
      title,
      changed_files,
      metadata.to_h["evaluation_reason"],
      metadata.to_h["action_type"],
      action_candidate&.title,
      action_candidate&.description,
      action_candidate&.action_type,
      action_candidate&.evaluation_reason
    ].compact.join(" ").downcase
  end

  def owner_approval_reason_code(reason)
    case reason
    when /お金|予算|費用|課金/
      "money_or_budget"
    when /方針|価格|料金|撤退|統合/
      "strategy_change"
    when /破壊|db:drop|db:reset/
      "destructive_production_change"
    when /法的|法務|規約|個人情報/
      "legal_risk"
    when /ブランド|ロゴ/
      "brand_change"
    when /高リスク/
      "high_risk"
    else
      "owner_only_decision"
    end
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
    return false if article_opportunity_codex_connection_only?

    execution_profile&.auto_deploy_allowed_for?(self) || false
  end

  def auto_merge_allowed?
    return false if article_opportunity_codex_connection_only?

    execution_profile&.auto_merge_allowed_for?(self) || false
  end

  def deploy_flow_label
    execution_profile&.deploy_flow_label_for(self) || "Execution Profile未設定のためPR作成まで"
  end

  def execution_metadata(operator:)
    profile = execution_profile
    article_opportunity_connection = article_opportunity_codex_connection_only?
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
      auto_deploy_enabled: article_opportunity_connection ? false : (profile&.auto_deploy_enabled? || false),
      auto_merge_enabled: article_opportunity_connection ? false : (profile&.auto_merge_enabled? || false),
      codex_submission_id: codex_submission&.id,
      codex_workspace_name: profile&.codex_workspace_name,
      codex_project_folder: profile&.codex_project_folder,
      codex_repository_url: profile&.effective_codex_repository_url,
      codex_base_branch: profile&.effective_codex_base_branch,
      codex_working_branch: codex_working_branch_name,
      codex_auto_submit_enabled: profile&.codex_auto_submit_enabled? || false,
      codex_auto_pr_enabled: profile&.codex_auto_pr_enabled? || false,
      codex_auto_merge_enabled: article_opportunity_connection ? false : (profile&.codex_auto_merge_enabled? || false),
      codex_auto_deploy_enabled: article_opportunity_connection ? false : (profile&.codex_auto_deploy_enabled? || false),
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

  def article_opportunity_codex_connection_only?
    metadata.to_h["deploy_disabled_reason"].to_s == "article_opportunity_codex_connection_only"
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
