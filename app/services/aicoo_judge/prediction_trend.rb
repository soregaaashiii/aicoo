module AicooJudge
  class PredictionTrend
    TrendPoint = Data.define(:date, :prediction_source, :average_calibration_score)

    def call
      grouped_records.map do |(date, source), scores|
        TrendPoint.new(
          date:,
          prediction_source: source,
          average_calibration_score: average(scores)
        )
      end.sort_by { |point| [ point.date, point.prediction_source ] }
    end

    def as_json(*)
      call.map do |point|
        {
          date: point.date.iso8601,
          prediction_source: point.prediction_source,
          average_calibration_score: point.average_calibration_score&.to_f
        }
      end
    end

    private

    def grouped_records
      (lab_records + revenue_records).each_with_object(Hash.new { |hash, key| hash[key] = [] }) do |record, grouped|
        next if record.scored_at.blank? || record.calibration_score.blank?

        grouped[[ record.scored_at.to_date, record.prediction_source ]] << record.calibration_score
      end
    end

    def lab_records
      AicooLabErrorMetric
        .joins(:aicoo_lab_prediction)
        .where.not(calibration_score: nil)
        .select("aicoo_lab_error_metrics.*, aicoo_lab_predictions.prediction_source AS judge_prediction_source")
        .map do |metric|
          TrendRecord.new(metric.judge_prediction_source, metric.calibration_score, metric.calculated_at)
        end
    end

    def revenue_records
      AicooRevenueExecution.scored.where.not(calibration_score: nil).map do |execution|
        TrendRecord.new(execution.prediction_source, execution.calibration_score, execution.measured_at)
      end
    end

    def average(values)
      numeric_values = values.compact.map(&:to_d)
      return nil if numeric_values.empty?

      numeric_values.sum / numeric_values.size
    end

    TrendRecord = Data.define(:prediction_source, :calibration_score, :scored_at)
  end
end
