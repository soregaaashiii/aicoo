class AicooLabScoringResultCreator
  RESULT_TYPES = %w[pv ctr conversion_rate].freeze

  def initialize(experiment, target_days:, failure: false, metrics: nil)
    @experiment = experiment
    @target_days = target_days.to_i
    @failure = failure
    @metrics = metrics || {}
    @landing_page = experiment.aicoo_lab_landing_page
  end

  def call
    experiment.transaction do
      RESULT_TYPES.each { |result_type| upsert_result!(result_type) }
      experiment.update!(scored_column => Time.current)
      experiment.recalculate_error_metrics!
    end
  end

  private

  attr_reader :experiment, :target_days, :failure, :metrics, :landing_page

  def upsert_result!(result_type)
    result = experiment.aicoo_lab_results.find_or_initialize_by(result_type:, target_days:)
    result.assign_attributes(
      actual_value: actual_value_for(result_type),
      actual_value_unit: unit_for(result_type),
      sample_size: pv,
      measured_at: Time.current
    )
    result.save!
  end

  def actual_value_for(result_type)
    return 0 if failure && result_type != "pv"

    case result_type
    when "pv"
      pv
    when "ctr"
      percent(metric_rate(:cta_rate, landing_page&.cta_rate))
    when "conversion_rate"
      percent(metric_rate(:signup_rate, landing_page&.signup_rate))
    end
  end

  def unit_for(result_type)
    result_type == "pv" ? "count" : "percent"
  end

  def pv
    @pv ||= metric_value(:pv, landing_page&.view_count.to_i).to_i
  end

  def metric_value(key, fallback)
    metrics[key] || metrics[key.to_s] || fallback
  end

  def metric_rate(key, fallback)
    metric_value(key, fallback)
  end

  def percent(rate)
    return 0 if rate.blank?

    rate.to_d * 100
  end

  def scored_column
    :"scored_#{target_days}d_at"
  end
end
