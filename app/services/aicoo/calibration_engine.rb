module Aicoo
  class CalibrationEngine
    MIN_SAMPLE_SIZE = ActionPredictionCalibration::MIN_SAMPLE_SIZE
    MIN_FACTOR = ActionPredictionCalibration::MIN_FACTOR
    MAX_FACTOR = ActionPredictionCalibration::MAX_FACTOR

    Result = Data.define(:calibrations, :logs) do
      def calibration_count
        calibrations.size
      end

      def pending_count
        calibrations.count { |calibration| calibration.respond_to?(:pending?) && calibration.pending? }
      end
    end

    def self.run!(source: "manual", aicoo_daily_run: nil)
      new(source:, aicoo_daily_run:).run!
    end

    def initialize(source: "manual", aicoo_daily_run: nil)
      @source = source
      @aicoo_daily_run = aicoo_daily_run
    end

    def run!
      calculated_at = Time.current
      calibrations = []
      logs = []

      grouped_results.each do |action_type, results|
        stats = calculate_stats(results)
        calibration = ActionPredictionCalibration.find_or_initialize_by(action_type:)
        old_profit_factor = calibration.profit_calibration_factor.to_d
        old_probability_factor = calibration.probability_calibration_factor.to_d

        profit_factor = stats.sample_count >= MIN_SAMPLE_SIZE ? safe_factor(stats.avg_actual_profit_yen, stats.avg_predicted_profit_yen) : 1.to_d
        probability_factor = stats.sample_count >= MIN_SAMPLE_SIZE ? safe_factor(stats.actual_success_rate, stats.avg_predicted_success_probability) : 1.to_d
        confidence_level = ActionPredictionCalibration.confidence_level_for(stats.sample_count)
        warning_level, warning_reason = ActionPredictionCalibration.warning_for(
          sample_count: stats.sample_count,
          old_profit_factor:,
          new_profit_factor: profit_factor
        )
        safe = safe_calibration?(confidence_level:, warning_level:, profit_factor:)
        effective_profit_factor = safe ? profit_factor : old_profit_factor
        effective_probability_factor = safe ? probability_factor : old_probability_factor
        factor_changed_at =
          if factor_changed?(old_profit_factor, profit_factor, old_probability_factor, probability_factor)
            calculated_at
          else
            calibration.factor_changed_at
          end
        approval_status = safe ? "auto_applied" : "pending"
        approval_reason = approval_reason(confidence_level:, warning_level:, warning_reason:)

        calibration.update!(
          sample_count: stats.sample_count,
          avg_predicted_profit_yen: stats.avg_predicted_profit_yen,
          avg_actual_profit_yen: stats.avg_actual_profit_yen,
          previous_profit_calibration_factor: old_profit_factor,
          profit_calibration_factor: effective_profit_factor,
          avg_predicted_success_probability: stats.avg_predicted_success_probability,
          actual_success_rate: stats.actual_success_rate,
          previous_probability_calibration_factor: old_probability_factor,
          probability_calibration_factor: effective_probability_factor,
          pending_profit_calibration_factor: safe ? nil : profit_factor,
          pending_probability_calibration_factor: safe ? nil : probability_factor,
          approval_status:,
          approval_requested_at: safe ? nil : calculated_at,
          approved_at: nil,
          rejected_at: nil,
          avg_profit_error_rate: stats.avg_profit_error_rate,
          last_calculated_at: calculated_at,
          confidence_level:,
          warning_level:,
          warning_reason: approval_reason,
          factor_changed_at:
        )

        log = ActionPredictionCalibrationLog.create!(
          action_type:,
          old_profit_calibration_factor: old_profit_factor,
          new_profit_calibration_factor: profit_factor,
          old_probability_calibration_factor: old_probability_factor,
          new_probability_calibration_factor: probability_factor,
          sample_count: stats.sample_count,
          avg_predicted_profit_yen: stats.avg_predicted_profit_yen,
          avg_actual_profit_yen: stats.avg_actual_profit_yen,
          avg_profit_error_rate: stats.avg_profit_error_rate,
          calculated_at:,
          source:,
          aicoo_daily_run:
        )

        calibrations << calibration
        logs << log
      end

      Result.new(calibrations:, logs:)
    end

    private

    attr_reader :source, :aicoo_daily_run

    Stats = Data.define(
      :sample_count,
      :avg_predicted_profit_yen,
      :avg_actual_profit_yen,
      :avg_predicted_success_probability,
      :actual_success_rate,
      :avg_profit_error_rate
    )

    def grouped_results
      eligible_results.group_by { |result| result.action_candidate.action_type.presence || "other" }
    end

    def eligible_results
      ActionResult.evaluated
                  .includes(:action_candidate)
                  .where.not(action_candidate_id: nil)
                  .where.not(predicted_expected_profit_yen: nil)
                  .select { |result| result.action_candidate.present? && !result.actual_profit_yen.nil? }
    end

    def calculate_stats(results)
      sample_count = results.size
      predicted_values = results.map { |result| result.predicted_expected_profit_yen.to_d }
      actual_values = results.map { |result| result.actual_profit_yen.to_d }
      predicted_probabilities = results.filter_map { |result| result.predicted_success_probability&.to_d }
      success_count = results.count { |result| successful?(result) }

      Stats.new(
        sample_count:,
        avg_predicted_profit_yen: average(predicted_values),
        avg_actual_profit_yen: average(actual_values),
        avg_predicted_success_probability: average(predicted_probabilities),
        actual_success_rate: sample_count.positive? ? success_count.to_d / sample_count : nil,
        avg_profit_error_rate: average_profit_error_rate(results)
      )
    end

    def successful?(result)
      result.actual_profit_yen.to_i.positive?
    end

    def average(values)
      compact_values = values.compact
      return nil if compact_values.empty?

      compact_values.sum / compact_values.size
    end

    def average_profit_error_rate(results)
      rates = results.filter_map do |result|
        predicted = result.predicted_expected_profit_yen.to_d
        next if predicted.zero?

        (predicted - result.actual_profit_yen.to_d).abs / predicted.abs
      end
      average(rates)
    end

    def safe_factor(numerator, denominator)
      denominator = denominator.to_d
      return 1.to_d if denominator.zero?

      clip(numerator.to_d / denominator)
    end

    def clip(value)
      [ [ value, MIN_FACTOR ].max, MAX_FACTOR ].min
    end

    def factor_changed?(old_profit_factor, profit_factor, old_probability_factor, probability_factor)
      old_profit_factor.to_d != profit_factor.to_d ||
        old_probability_factor.to_d != probability_factor.to_d
    end

    def safe_calibration?(confidence_level:, warning_level:, profit_factor:)
      warning_level == "none" &&
        confidence_level != "low" &&
        profit_factor.to_d > 0.2.to_d &&
        profit_factor.to_d < 2.5.to_d
    end

    def approval_reason(confidence_level:, warning_level:, warning_reason:)
      reasons = []
      reasons << "信頼度がlowのため承認待ちです" if confidence_level == "low"
      reasons << warning_reason if warning_reason.present?
      reasons.presence&.join(" / ")
    end
  end
end
