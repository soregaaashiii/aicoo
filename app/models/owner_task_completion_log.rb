class OwnerTaskCompletionLog < ApplicationRecord
  ACTION_RESULTS = %w[success failed skipped].freeze

  validates :task_type, :action_label, :action_result, :completed_at, presence: true
  validates :action_result, inclusion: { in: ACTION_RESULTS }

  scope :recent, -> { order(completed_at: :desc, created_at: :desc) }

  def self.record!(task_type:, target:, action_label:, action_result:, message:, metadata: {})
    create!(
      task_type:,
      target_type: target.class.name,
      target_id: target.id,
      action_label:,
      action_result:,
      message:,
      completed_at: Time.current,
      metadata:
    )
  end

  def self.record_success!(task_type:, target:, action_label:, message:, metadata: {})
    record!(task_type:, target:, action_label:, action_result: "success", message:, metadata:)
  end
end
