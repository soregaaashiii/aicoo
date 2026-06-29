class AicooPipelineRun < ApplicationRecord
  PIPELINE_TYPES = %w[idea_pipeline business].freeze
  STATUSES = %w[running waiting approval_waiting retry_waiting budget_blocked blocked completed pivoted ended].freeze
  STAGES = %w[discovery score serp lp publish measure improve deploy learning decision].freeze

  belongs_to :business, optional: true
  belongs_to :idea_pipeline_item, optional: true
  belongs_to :aicoo_lab_landing_page, optional: true

  validates :pipeline_type, inclusion: { in: PIPELINE_TYPES }
  validates :status, inclusion: { in: STATUSES }
  validates :current_stage, inclusion: { in: STAGES }
  validates :retry_count, numericality: { greater_than_or_equal_to: 0 }

  scope :active, -> { where.not(status: %w[completed ended]) }
  scope :stopped_for_owner, -> { where(status: %w[waiting approval_waiting retry_waiting budget_blocked blocked pivoted]) }
  scope :recent, -> { order(updated_at: :desc) }

  def stage_state(stage)
    stage_states.to_h[stage.to_s] || {}
  end

  def current_stage_state
    stage_state(current_stage)
  end

  def stopped?
    status.in?(%w[waiting approval_waiting retry_waiting budget_blocked blocked pivoted])
  end

  def display_title
    idea_pipeline_item&.title.presence || business&.name.presence || "AICOO Pipeline ##{id}"
  end

  def target_path
    if idea_pipeline_item
      Rails.application.routes.url_helpers.admin_idea_pipeline_path(idea_pipeline_item)
    elsif business
      Rails.application.routes.url_helpers.business_path(business)
    else
      Rails.application.routes.url_helpers.admin_idea_pipeline_index_path
    end
  end
end
