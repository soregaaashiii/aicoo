class PipelineRecoveryLog < ApplicationRecord
  ACTIONS = %w[retry skip approve stop end request_approval detect].freeze
  STUCK_REASONS = %w[
    waiting_approval
    waiting_data
    waiting_budget
    missing_google_connection
    missing_serp_key
    missing_execution_profile
    codex_failed
    deploy_failed
    api_failed
    validation_failed
    unknown
  ].freeze

  belongs_to :aicoo_pipeline_run
  belongs_to :business, optional: true

  validates :stage, presence: true, inclusion: { in: AicooPipelineRun::STAGES }
  validates :stuck_reason, inclusion: { in: STUCK_REASONS }
  validates :action, inclusion: { in: ACTIONS }

  scope :recent, -> { order(executed_at: :desc, created_at: :desc) }
end
