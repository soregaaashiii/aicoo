module Aicoo
  class PracticalitySummary
    Summary = Data.define(
      :average_practicality_score,
      :low_practicality_count,
      :top_candidates,
      :adoption_rates,
      :completion_rates,
      :execution_rates
    )
    Rate = Data.define(:bucket, :total_count, :positive_count, :rate)

    BUCKETS = {
      "high" => 70..100,
      "medium" => 30...70,
      "low" => 0...30
    }.freeze

    def call
      candidates = ActionCandidate.where.not(practicality_score: nil)

      Summary.new(
        average_practicality_score: average_score(candidates),
        low_practicality_count: candidates.where("practicality_score < ?", 30).count,
        top_candidates: candidates.includes(:business).order(practicality_score: :desc, final_score: :desc).limit(5),
        adoption_rates: rates_for(OwnerDecisionLog.last_30_days, OwnerDecisionLog::POSITIVE_DECISIONS),
        completion_rates: rates_for(OwnerDecisionLog.last_30_days, %w[complete]),
        execution_rates: rates_for(OwnerDecisionLog.last_30_days, OwnerDecisionLog::EXECUTION_DECISIONS)
      )
    end

    private

    def average_score(candidates)
      return 0.to_d if candidates.count.zero?

      (candidates.sum(:practicality_score).to_d / candidates.count.to_d).round(1)
    end

    def rates_for(logs, positive_decisions)
      BUCKETS.map do |bucket, range|
        bucket_logs = logs.select { |log| range.cover?(practicality_score_for(log)) }
        positive_count = bucket_logs.count { |log| positive_decisions.include?(log.decision_type) }
        Rate.new(
          bucket:,
          total_count: bucket_logs.size,
          positive_count:,
          rate: ratio(positive_count, bucket_logs.size)
        )
      end
    end

    def practicality_score_for(log)
      log.metadata.to_h.dig("practicality", "practicality_score").to_d
    end

    def ratio(numerator, denominator)
      return 0.to_d if denominator.to_i.zero?

      (numerator.to_d / denominator.to_d).round(3)
    end
  end
end
