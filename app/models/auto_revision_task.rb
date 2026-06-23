class AutoRevisionTask < ApplicationRecord
  STATUSES = %w[
    draft
    waiting_approval
    approved
    ready_for_codex
    sent_to_codex
    running
    succeeded
    partial_succeeded
    failed
    canceled
  ].freeze
  RISK_LEVELS = %w[low medium high].freeze
  ACTIVE_STATUSES = %w[draft waiting_approval approved ready_for_codex sent_to_codex running].freeze
  CODEX_QUEUE_STATUSES = %w[ready_for_codex sent_to_codex running].freeze
  STALE_AFTER = 7.days

  belongs_to :action_candidate
  belongs_to :business
  has_one :codex_quality_check, dependent: :destroy

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

  def self.from_action_candidate(action_candidate, generated_by: "owner")
    active.find_by(action_candidate:) ||
      create!(
        action_candidate:,
        business: action_candidate.business,
        title: action_candidate.title,
        execution_prompt: action_candidate.execution_prompt.presence || action_candidate.evaluation_reason,
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
    update!(status: "ready_for_codex", approved_at: Time.current)
  end

  def mark_sent_to_codex!
    update!(status: "sent_to_codex", sent_to_codex_at: sent_to_codex_at || Time.current)
  end

  def start_implementation!
    started_time = Time.current
    update!(
      status: "running",
      started_at: started_at || started_time,
      started_running_at: started_running_at || started_time
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
        "quality_review_required" => codex_quality_check&.review_required? || false
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
    %w[succeeded partial_succeeded].include?(status)
  end

  def codex_prompt
    <<~PROMPT
      目的:
      #{title}

      背景:
      AICOOが生成したActionCandidateを、Codexへ渡せる実行単位として整理したAutoRevisionTaskです。
      タスクID: AutoRevisionTask ##{id}
      対象事業: #{business.name}
      action_type: #{metadata.to_h["action_type"].presence || action_candidate.action_type}
      risk_level: #{risk_level}

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

      確認コマンド:
      - bin/rails test
      - bin/rails zeitwerk:check
      - RUBOCOP_CACHE_ROOT=tmp/rubocop_cache bundle exec rubocop
      #{migration_confirmation_commands}

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

  private

  def set_defaults
    self.status = "draft" if status.blank?
    self.risk_level = "medium" if risk_level.blank?
    self.priority_score = 0 if priority_score.blank?
    self.generated_by = "aicoo" if generated_by.blank?
    self.metadata = {} if metadata.blank?
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
end
