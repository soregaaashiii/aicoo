module Aicoo
  class LearningLoopQualityReport
    ActionTypeSummary = Data.define(
      :action_type,
      :sample_count,
      :avg_error_rate,
      :avg_profit_prediction,
      :avg_profit_actual
    )
    ActionError = Data.define(
      :action_result,
      :action_candidate,
      :title,
      :predicted_profit,
      :actual_profit,
      :error_rate
    )
    Result = Data.define(
      :generated_at,
      :total_predictions,
      :total_evaluated,
      :prediction_accuracy_score,
      :profit_error_rate,
      :success_probability_error,
      :calibration_effectiveness_score,
      :learning_trend,
      :strongest_action_types,
      :weakest_action_types,
      :most_overestimated_actions,
      :most_underestimated_actions,
      :warnings
    )

    MIN_ACTION_TYPE_SAMPLE = 2

    def call
      Result.new(
        generated_at: Time.current,
        total_predictions: results.count,
        total_evaluated: evaluated_results.count,
        prediction_accuracy_score: accuracy_score(evaluated_results),
        profit_error_rate: average_error_rate(evaluated_results),
        success_probability_error:,
        calibration_effectiveness_score:,
        learning_trend:,
        strongest_action_types: strongest_action_types,
        weakest_action_types: weakest_action_types,
        most_overestimated_actions: most_overestimated_actions,
        most_underestimated_actions: most_underestimated_actions,
        warnings:
      )
    end

    private

    def results
      @results ||= ActionResult.includes(:action_candidate).where.not(predicted_expected_profit_yen: nil).to_a
    end

    def evaluated_results
      @evaluated_results ||= results.select { |result| result.evaluation_status == "evaluated" }
    end

    def average_error_rate(scope)
      rates = scope.map { |result| error_rate(result) }
      return if rates.empty?

      rates.sum / rates.size
    end

    def accuracy_score(scope)
      rate = average_error_rate(scope)
      return if rate.nil?

      ((1 - [ rate, 1.to_d ].min) * 100).round
    end

    def success_probability_error
      values = evaluated_results.filter_map do |result|
        next if result.predicted_success_probability.nil?

        actual_success = result.actual_profit_yen.to_i.positive? ? 1.to_d : 0.to_d
        (result.predicted_success_probability.to_d - actual_success).abs
      end
      return if values.empty?

      values.sum / values.size
    end

    def calibration_effectiveness_score
      logs = ActionPredictionCalibrationLog.where.not(avg_profit_error_rate: nil).order(:calculated_at, :created_at).to_a
      return "N/A" if logs.size < 2

      before = logs.first.avg_profit_error_rate.to_d
      after = logs.last.avg_profit_error_rate.to_d
      return "N/A" if before.zero?

      improvement = (before - after) / before
      ([ [ improvement, 0.to_d ].max, 1.to_d ].min * 100).round
    end

    def learning_trend
      recent_score = accuracy_score(results_in_range(30.days.ago.to_date..Date.current))
      previous_score = accuracy_score(results_in_range(60.days.ago.to_date...30.days.ago.to_date))
      return "stable" if recent_score.nil? || previous_score.nil?

      delta = recent_score - previous_score
      return "improving" if delta > 2
      return "declining" if delta < -2

      "stable"
    end

    def results_in_range(range)
      evaluated_results.select { |result| range.cover?(result.evaluated_on) }
    end

    def action_type_summaries
      @action_type_summaries ||= evaluated_results.group_by { |result| result.action_candidate&.action_type || "unknown" }.filter_map do |action_type, grouped|
        next if grouped.size < MIN_ACTION_TYPE_SAMPLE

        ActionTypeSummary.new(
          action_type:,
          sample_count: grouped.size,
          avg_error_rate: average_error_rate(grouped),
          avg_profit_prediction: average_predicted_profit(grouped),
          avg_profit_actual: average_actual_profit(grouped)
        )
      end
    end

    def strongest_action_types
      action_type_summaries.sort_by { |summary| [ summary.avg_error_rate || 1.to_d, -summary.sample_count ] }.first(5)
    end

    def weakest_action_types
      action_type_summaries.sort_by { |summary| [ -(summary.avg_error_rate || 0.to_d), -summary.sample_count ] }.first(5)
    end

    def most_overestimated_actions
      evaluated_results.select { |result| result.predicted_expected_profit_yen.to_i > result.actual_profit_yen.to_i }
                       .sort_by { |result| -(result.predicted_expected_profit_yen.to_i - result.actual_profit_yen.to_i) }
                       .first(10)
                       .map { |result| action_error(result) }
    end

    def most_underestimated_actions
      evaluated_results.select { |result| result.actual_profit_yen.to_i > result.predicted_expected_profit_yen.to_i }
                       .sort_by { |result| -(result.actual_profit_yen.to_i - result.predicted_expected_profit_yen.to_i) }
                       .first(10)
                       .map { |result| action_error(result) }
    end

    def warnings
      [].tap do |items|
        items << "evaluated件数不足" if evaluated_results.size < 10
        items << "calibrationデータ不足" if calibration_effectiveness_score == "N/A"
        items << "success probability精度低下" if success_probability_error.to_d > 0.4
        items << "Learning Trend declining" if learning_trend == "declining"
        if weakest_action_types.any? && weakest_action_types.first.avg_error_rate.to_d > 1
          items << "#{weakest_action_types.first.action_type} が極端に外れています"
        end
      end
    end

    def error_rate(result)
      predicted = result.predicted_expected_profit_yen.to_i
      actual = result.actual_profit_yen.to_i
      return 0.to_d if predicted.zero? && actual.zero?
      return 1.to_d if predicted.zero?

      (predicted - actual).abs.to_d / predicted.abs
    end

    def average_predicted_profit(grouped)
      grouped.sum { |result| result.predicted_expected_profit_yen.to_i }.to_d / grouped.size
    end

    def average_actual_profit(grouped)
      grouped.sum { |result| result.actual_profit_yen.to_i }.to_d / grouped.size
    end

    def action_error(result)
      ActionError.new(
        action_result: result,
        action_candidate: result.action_candidate,
        title: result.action_candidate&.title || "ActionResult ##{result.id}",
        predicted_profit: result.predicted_expected_profit_yen.to_i,
        actual_profit: result.actual_profit_yen.to_i,
        error_rate: error_rate(result)
      )
    end
  end
end
