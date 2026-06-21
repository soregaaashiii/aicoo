module AicooJudge
  class PredictionAnalyzer
    SOURCES = %w[human lab revenue].freeze

    SourceSummary = Data.define(:prediction_source, :prediction_count, :average_error_rate, :average_calibration_score)
    Result = Data.define(:prediction_count, :average_error_rate, :average_calibration_score, :source_summaries, :ranking, :winner)

    def call
      summaries = SOURCES.map { |source| summary_for(source) }
      scored_summaries = summaries.select { |summary| summary.prediction_count.positive? }

      Result.new(
        prediction_count: scored_records.count,
        average_error_rate: average(scored_records.map(&:error_rate)),
        average_calibration_score: average(scored_records.map(&:calibration_score)),
        source_summaries: summaries,
        ranking: scored_summaries.sort_by { |summary| -summary.average_calibration_score.to_d },
        winner: scored_summaries.max_by { |summary| summary.average_calibration_score.to_d }
      )
    end

    private

    def summary_for(source)
      records = scored_records.select { |record| record.prediction_source == source }

      SourceSummary.new(
        prediction_source: source,
        prediction_count: records.count,
        average_error_rate: average(records.map(&:error_rate)),
        average_calibration_score: average(records.map(&:calibration_score))
      )
    end

    def scored_records
      @scored_records ||= lab_records + revenue_records
    end

    def lab_records
      AicooLabErrorMetric
        .joins(:aicoo_lab_prediction)
        .where.not(calibration_score: nil)
        .select("aicoo_lab_error_metrics.*, aicoo_lab_predictions.prediction_source AS judge_prediction_source")
        .map do |metric|
          ScoredPrediction.new(
            prediction_source: metric.judge_prediction_source,
            error_rate: metric.error_rate,
            calibration_score: metric.calibration_score,
            scored_at: metric.calculated_at
          )
        end
    end

    def revenue_records
      AicooRevenueExecution.scored.where.not(calibration_score: nil).map do |execution|
        ScoredPrediction.new(
          prediction_source: execution.prediction_source,
          error_rate: execution.error_rate,
          calibration_score: execution.calibration_score,
          scored_at: execution.measured_at
        )
      end
    end

    def average(values)
      numeric_values = values.compact.map(&:to_d)
      return nil if numeric_values.empty?

      numeric_values.sum / numeric_values.size
    end

    ScoredPrediction = Data.define(:prediction_source, :error_rate, :calibration_score, :scored_at)
  end
end
