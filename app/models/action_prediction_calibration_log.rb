class ActionPredictionCalibrationLog < ApplicationRecord
  SOURCES = %w[
    manual
    daily_run
    step_recovery
    action_result_evaluator
    activity_learning_pipeline
    action_result_create
    action_result_update
    owner_auto_revision_action_result
    approval
    rejected
  ].freeze

  belongs_to :aicoo_daily_run, optional: true

  validates :action_type, presence: true
  validates :source, inclusion: { in: SOURCES }
end
