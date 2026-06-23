class ActionExecutionLog < ApplicationRecord
  STATUSES = %w[completed partial over_completed skipped changed failed].freeze

  belongs_to :action_candidate
  belongs_to :business
  belongs_to :action_result, optional: true
  belongs_to :linked_revenue_event, class_name: "RevenueEvent", foreign_key: :revenue_event_id, optional: true
  has_many :revenue_events, dependent: :nullify

  before_validation :copy_action_candidate_defaults
  before_save :calculate_variance

  validates :planned_action, :actual_action, presence: true
  validates :status, inclusion: { in: STATUSES }
  validates :planned_quantity, :actual_quantity,
            numericality: { greater_than_or_equal_to: 0 }, allow_nil: true
  validates :completion_rate, :variance_quantity, numericality: true, allow_nil: true

  scope :recent, -> { order(finished_at: :desc, created_at: :desc) }

  def auto_linked_action_result?
    metadata.to_h["auto_linked_action_result_id"].present?
  end

  def auto_linked_revenue_event?
    metadata.to_h["auto_linked_revenue_event_id"].present?
  end

  def auto_linked_at
    value = metadata.to_h["auto_linked_at"]
    Time.zone.parse(value) if value.present?
  rescue ArgumentError, TypeError
    nil
  end

  def auto_link_method
    metadata.to_h["auto_link_method"]
  end

  private

  def copy_action_candidate_defaults
    self.business ||= action_candidate&.business
    self.planned_action = default_planned_action if planned_action.blank?
    self.planned_quantity = inferred_planned_quantity if planned_quantity.blank?
    self.status = inferred_status if status.blank?
  end

  def calculate_variance
    self.completion_rate = calculate_completion_rate
    self.variance_quantity = calculate_variance_quantity
    self.status = inferred_status if status.blank? || status_changed_by_calculation?
  end

  def default_planned_action
    [
      action_candidate&.title,
      action_candidate&.execution_prompt.presence || action_candidate&.description
    ].compact.join("\n")
  end

  def inferred_planned_quantity
    source = [
      action_candidate&.title,
      action_candidate&.execution_prompt,
      action_candidate&.description
    ].compact.join("\n")
    source[/(\d+(?:\.\d+)?)\s*(?:件|本|記事|店舗|個|回)/, 1]
  end

  def calculate_completion_rate
    return nil if planned_quantity.blank? || planned_quantity.to_d.zero? || actual_quantity.blank?

    actual_quantity.to_d / planned_quantity.to_d
  end

  def calculate_variance_quantity
    return nil if planned_quantity.blank? || actual_quantity.blank?

    actual_quantity.to_d - planned_quantity.to_d
  end

  def inferred_status
    return "failed" if actual_action.blank? && actual_quantity.to_d.zero?
    return "completed" if planned_quantity.blank? || planned_quantity.to_d.zero? || actual_quantity.blank?

    rate = actual_quantity.to_d / planned_quantity.to_d
    return "skipped" if rate.zero?
    return "partial" if rate < 1
    return "completed" if rate == 1

    "over_completed"
  end

  def status_changed_by_calculation?
    new_record? && !STATUSES.include?(status)
  end
end
