class AicooSetting < ApplicationRecord
  STRATEGIC_WEIGHT_ATTRIBUTES = %i[
    long_term_profit_weight
    short_term_profit_weight
    learning_weight
    automation_weight
    exploration_weight
  ].freeze

  validates(*STRATEGIC_WEIGHT_ATTRIBUTES, numericality: { only_integer: true, greater_than_or_equal_to: 0, less_than_or_equal_to: 100 })
  validates :strategic_learning_max_boost_rate,
            :strategic_learning_max_penalty_rate,
            :strategic_learning_warning_threshold_rate,
            numericality: { greater_than_or_equal_to: 0, less_than_or_equal_to: 1 }
  validates :strategic_learning_decision_log_min_count,
            numericality: { only_integer: true, greater_than_or_equal_to: 0 }

  def self.current
    first_or_create!
  end

  def owner_queue_allows_risk?(risk_level)
    case risk_level
    when "low"
      auto_queue_low_risk_enabled?
    when "medium"
      auto_queue_medium_risk_enabled?
    when "high"
      auto_queue_high_risk_enabled?
    else
      false
    end
  end

  def strategic_weights_extremely_skewed?
    weights = STRATEGIC_WEIGHT_ATTRIBUTES.map { |attribute| public_send(attribute).to_i }
    return false if weights.sum.zero?

    weights.max >= 80 || weights.count(&:positive?) <= 1
  end
end
