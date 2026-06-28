class IdeaPipelineItem < ApplicationRecord
  STATUSES = %w[
    idea scored serp_pending serp_evaluated serp_blocked lp_generated published
    learning_evaluated mvp_spec_ready continuing improving ended
  ].freeze
  STAGES = %w[idea score serp lp publish learning mvp].freeze
  MVP_DECISIONS = %w[develop continue_lp improve end].freeze

  belongs_to :business, optional: true
  belongs_to :aicoo_lab_experiment, optional: true
  belongs_to :aicoo_lab_landing_page, optional: true

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

  def lp_url
    return unless aicoo_lab_landing_page&.published_slug.present?

    Rails.application.routes.url_helpers.public_lp_path(aicoo_lab_landing_page.published_slug)
  end
end
