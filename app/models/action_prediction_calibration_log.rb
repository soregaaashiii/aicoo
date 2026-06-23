class ActionPredictionCalibrationLog < ApplicationRecord
  SOURCES = %w[manual daily_run].freeze

  belongs_to :aicoo_daily_run, optional: true

  validates :action_type, presence: true
  validates :source, inclusion: { in: SOURCES }
end
