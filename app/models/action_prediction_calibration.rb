class ActionPredictionCalibration < ApplicationRecord
  MIN_SAMPLE_SIZE = 10
  MIN_FACTOR = 0.1.to_d
  MAX_FACTOR = 3.0.to_d
  CONFIDENCE_LEVELS = %w[low medium high].freeze
  WARNING_LEVELS = %w[none notice warning danger].freeze
  APPROVAL_STATUSES = %w[auto_applied pending approved rejected].freeze

  validates :action_type, presence: true, uniqueness: true
  validates :sample_count, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :confidence_level, inclusion: { in: CONFIDENCE_LEVELS }
  validates :warning_level, inclusion: { in: WARNING_LEVELS }
  validates :approval_status, inclusion: { in: APPROVAL_STATUSES }
  validates :profit_calibration_factor,
            :probability_calibration_factor,
            numericality: { greater_than_or_equal_to: MIN_FACTOR, less_than_or_equal_to: MAX_FACTOR }

  def self.for_action_type(action_type)
    find_by(action_type:) || new(
      action_type:,
      sample_count: 0,
      profit_calibration_factor: 1.0,
      probability_calibration_factor: 1.0,
      confidence_level: "low",
      warning_level: "none",
      approval_status: "auto_applied"
    )
  end

  def active?
    sample_count.to_i >= MIN_SAMPLE_SIZE
  end

  def profit_factor
    active? ? profit_calibration_factor.to_d : 1.to_d
  end

  def probability_factor
    active? ? probability_calibration_factor.to_d : 1.to_d
  end

  def pending?
    approval_status == "pending"
  end

  def approve!(note: nil)
    old_profit_factor = profit_calibration_factor
    old_probability_factor = probability_calibration_factor
    new_profit_factor = pending_profit_calibration_factor || profit_calibration_factor
    new_probability_factor = pending_probability_calibration_factor || probability_calibration_factor

    update!(
      profit_calibration_factor: new_profit_factor,
      probability_calibration_factor: new_probability_factor,
      approved_profit_calibration_factor: new_profit_factor,
      approved_probability_calibration_factor: new_probability_factor,
      pending_profit_calibration_factor: nil,
      pending_probability_calibration_factor: nil,
      approval_status: "approved",
      approved_at: Time.current,
      rejected_at: nil,
      approval_note: note.presence || approval_note,
      factor_changed_at: Time.current
    )
    create_decision_log!(
      source: "approval",
      old_profit_factor:,
      new_profit_factor:,
      old_probability_factor:,
      new_probability_factor:
    )
  end

  def reject!(note: nil)
    old_profit_factor = profit_calibration_factor
    old_probability_factor = probability_calibration_factor
    rejected_profit_factor = pending_profit_calibration_factor || profit_calibration_factor
    rejected_probability_factor = pending_probability_calibration_factor || probability_calibration_factor

    update!(
      pending_profit_calibration_factor: nil,
      pending_probability_calibration_factor: nil,
      approval_status: "rejected",
      rejected_at: Time.current,
      approval_note: note.presence || approval_note
    )
    create_decision_log!(
      source: "rejected",
      old_profit_factor:,
      new_profit_factor: rejected_profit_factor,
      old_probability_factor:,
      new_probability_factor: rejected_probability_factor
    )
  end

  def self.confidence_level_for(sample_count)
    count = sample_count.to_i
    return "high" if count >= 30
    return "medium" if count >= MIN_SAMPLE_SIZE

    "low"
  end

  def self.warning_for(sample_count:, old_profit_factor:, new_profit_factor:)
    reasons = []
    level = "none"
    old_factor = old_profit_factor.to_d
    new_factor = new_profit_factor.to_d

    if new_factor <= 0.2.to_d || new_factor >= 2.5.to_d
      level = "danger"
      reasons << "利益補正係数が極端です"
    end

    if old_factor.positive?
      change_rate = (new_factor - old_factor).abs / old_factor
      if change_rate >= 0.5.to_d
        level = "warning" if level == "none"
        reasons << "利益補正係数が前回比50%以上変化しました"
      end
      if sample_count.to_i < 30 && change_rate >= 0.5.to_d
        level = "warning" if level == "none"
        reasons << "サンプル数が少ない状態で係数が大きく動いています"
      end
    end

    [ level, reasons.join(" / ").presence ]
  end

  private

  def create_decision_log!(source:, old_profit_factor:, new_profit_factor:, old_probability_factor:, new_probability_factor:)
    ActionPredictionCalibrationLog.create!(
      action_type:,
      old_profit_calibration_factor: old_profit_factor,
      new_profit_calibration_factor: new_profit_factor,
      old_probability_calibration_factor: old_probability_factor,
      new_probability_calibration_factor: new_probability_factor,
      sample_count:,
      avg_predicted_profit_yen:,
      avg_actual_profit_yen:,
      avg_profit_error_rate:,
      calculated_at: Time.current,
      source:
    )
  end
end
