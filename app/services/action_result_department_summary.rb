class ActionResultDepartmentSummary
  Summary = Data.define(
    :department,
    :label,
    :executed_count,
    :success_count,
    :success_rate,
    :predicted_expected_profit_total_yen,
    :actual_profit_total_yen,
    :prediction_gap_yen,
    :average_confidence_score
  )

  DISPLAY_DEPARTMENTS = %w[revenue lab new_business].freeze

  def initialize(scope: ActionResult.includes(:action_candidate).all)
    @scope = scope
  end

  def summaries
    DISPLAY_DEPARTMENTS.map { |department| summary_for(department) }
  end

  def summary_for(department)
    records = records_for(department)
    evaluated = records.select { |record| record.evaluation_status == "evaluated" }
    predicted_total = evaluated.sum { |record| record.predicted_expected_profit_yen.to_i }
    actual_total = evaluated.sum { |record| record.actual_profit_yen.to_i }

    Summary.new(
      department:,
      label: ActionCandidateDepartmentRanking::DEPARTMENTS.fetch(department),
      executed_count: records.count,
      success_count: evaluated.count { |record| success?(record) },
      success_rate: evaluated.any? ? evaluated.count { |record| success?(record) }.to_d / evaluated.count : nil,
      predicted_expected_profit_total_yen: predicted_total,
      actual_profit_total_yen: actual_total,
      prediction_gap_yen: actual_total - predicted_total,
      average_confidence_score: average(evaluated.map { |record| record.action_candidate.confidence_score })
    )
  end

  private

  attr_reader :scope

  def records_for(department)
    scope.to_a.select { |record| record.action_candidate&.department == department }
  end

  def success?(record)
    return false unless record.evaluation_status == "evaluated"

    record.actual_profit_yen.to_i.positive? || record.prediction_error_rate.to_d <= 0.5
  end

  def average(values)
    numeric_values = values.compact.map(&:to_d)
    return nil if numeric_values.empty?

    numeric_values.sum / numeric_values.size
  end
end
