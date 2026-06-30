class RevenueEvent < ApplicationRecord
  include AicooActivityTrackable

  EVENT_TYPES = %w[revenue expense].freeze

  belongs_to :business
  belongs_to :action_candidate, optional: true
  belongs_to :action_result, optional: true
  belongs_to :action_execution_log, optional: true

  enum :event_type, {
    revenue: "revenue",
    expense: "expense"
  }, validate: true

  before_validation :complete_learning_loop_links

  validates :occurred_on, presence: true
  validates :amount, numericality: { only_integer: true, greater_than: 0 }

  private

  def complete_learning_loop_links
    complete_from_action_result if action_result
    complete_from_action_execution_log if action_execution_log
    self.business ||= action_candidate&.business || action_result&.business || action_execution_log&.business
  end

  def complete_from_action_result
    self.action_candidate ||= action_result.action_candidate
    self.action_execution_log ||= action_result.action_execution_logs.recent.first
  end

  def complete_from_action_execution_log
    self.action_candidate ||= action_execution_log.action_candidate
    self.action_result ||= action_execution_log.action_result
  end
end
