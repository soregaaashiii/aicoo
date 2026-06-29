class IdeaPipelineItem < ApplicationRecord
  STATUSES = %w[
    idea scored approved manually_approved owner_approved serp_pending serp_running
    serp_evaluated serp_blocked serp_skipped serp_not_configured rejected archived duplicate unsafe
    lp_generated published
    learning_evaluated mvp_spec_ready continuing improving ended
  ].freeze
  STAGES = %w[idea score serp lp publish learning mvp].freeze
  MVP_DECISIONS = %w[develop continue_lp improve end].freeze

  belongs_to :business, optional: true
  belongs_to :aicoo_lab_experiment, optional: true
  belongs_to :aicoo_lab_landing_page, optional: true
  has_one :aicoo_pipeline_run, dependent: :destroy

  validates :title, presence: true
  validates :status, inclusion: { in: STATUSES }
  validates :current_stage, inclusion: { in: STAGES }
  validates :mvp_decision, inclusion: { in: MVP_DECISIONS }, allow_blank: true
  validates :final_score, :market_score, :competition_score, :monetization_score,
            :automation_score, :serp_difficulty_score, :maintenance_cost_score,
            :ai_implementation_score, :difficulty_score,
            numericality: { greater_than_or_equal_to: 0, less_than_or_equal_to: 100 },
            allow_nil: true
  validates :development_hours, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true
  validates :expected_profit_yen, numericality: { only_integer: true, greater_than_or_equal_to: 0 }, allow_nil: true

  scope :recent, -> { order(created_at: :desc) }
  scope :by_priority, -> { order(Arel.sql("final_score DESC NULLS LAST, created_at DESC")) }
  scope :ready_for_serp, -> { where(status: "scored").where("final_score >= ?", 60).by_priority }

  BLOCKED_LP_GENERATION_STATUSES = %w[rejected archived duplicate unsafe].freeze
  LP_GENERATION_APPROVAL_STATUSES = %w[approved manually_approved owner_approved serp_skipped].freeze

  def stage_done?(stage)
    case stage.to_s
    when "idea"
      true
    when "score"
      evaluated_at.present?
    when "serp"
      serp_evaluated_at.present?
    when "lp"
      aicoo_lab_landing_page_id.present?
    when "publish"
      published_at.present? || aicoo_lab_landing_page&.publicly_visible?
    when "learning"
      learning_evaluated_at.present?
    when "mvp"
      mvp_decided_at.present?
    else
      false
    end
  end

  def serp_passed?
    serp_snapshot.to_h["passed"] == true
  end

  def serp_status
    snapshot_status = serp_snapshot.to_h["status"].presence
    return "serp_passed" if serp_passed?
    return "serp_skipped" if status == "serp_skipped" || snapshot_status == "skipped"
    return "serp_running" if status == "serp_running"
    return "serp_failed" if snapshot_status == "failed"
    return "serp_not_configured" if snapshot_status == "blocked"
    return "serp_pending" if serp_evaluated_at.blank?

    "serp_failed"
  end

  def serp_status_label
    {
      "serp_pending" => "未実行",
      "serp_running" => "実行中",
      "serp_passed" => "合格",
      "serp_failed" => "不合格",
      "serp_skipped" => "スキップ",
      "serp_not_configured" => "未設定"
    }.fetch(serp_status)
  end

  def lp_generation_blocked?
    BLOCKED_LP_GENERATION_STATUSES.include?(status) || aicoo_lab_landing_page_id.present?
  end

  def lp_generation_block_reason
    return "already_converted" if aicoo_lab_landing_page_id.present?

    status if BLOCKED_LP_GENERATION_STATUSES.include?(status)
  end

  def lp_generation_allowed?
    !lp_generation_blocked?
  end

  def score_passed?
    status == "scored" && final_score.to_d >= 60
  end

  def serp_warning_for_lp_generation
    return if serp_passed?
    if serp_snapshot.to_h["reason_code"] == "score_below_serp_threshold"
      return "final_scoreが低いためSERPはスキップしました。承認済みのためLP生成は可能です。" if lp_generation_approval_state != "not_approved"

      return "final_scoreが低いためSERPはスキップしました。Owner承認後にLP生成できます。"
    end

    "SERP検証は未実行です。精度は下がりますが、LP生成は可能です。"
  end

  def lp_generation_approval_state
    return status if LP_GENERATION_APPROVAL_STATUSES.include?(status)
    return "serp_passed" if serp_passed?
    return "score_passed" if score_passed?

    "not_approved"
  end

  def lp_generation_failure_reason
    case lp_generation_block_reason
    when "already_converted"
      "このIdeaはすでにLP生成済みです。既存LPを編集または公開してください。"
    when "rejected"
      "このIdeaは却下済みのためLP生成できません。再度検証する場合は状態を承認済みに戻してください。"
    when "archived"
      "このIdeaはアーカイブ済みのためLP生成できません。"
    when "duplicate"
      "このIdeaは重複候補のためLP生成できません。元の候補を確認してください。"
    when "unsafe"
      "このIdeaは安全性確認が必要なためLP生成を停止しています。"
    else
      "SERP未実行ですが、承認済みまたは検証可能な状態のためLP生成は可能です。処理条件を確認してください。"
    end
  end

  def lp_generation_condition_summary
    "停止条件: rejected / archived / duplicate / unsafe / already_converted。SERP未実行・未設定は警告のみでLP生成可能。"
  end

  def lp_generation_debug_context
    {
      item_id: id,
      status:,
      serp_status:,
      approval_state: lp_generation_approval_state,
      generation_conditions: lp_generation_condition_summary,
      lp_generation_block_reason: lp_generation_block_reason.presence,
      final_score: final_score&.to_s
    }
  end

  def lp_url
    return unless aicoo_lab_landing_page&.published_slug.present?

    Rails.application.routes.url_helpers.public_lp_path(aicoo_lab_landing_page.published_slug)
  end
end
