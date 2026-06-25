module Aicoo
  class EvidenceSummary
    BucketRate = Data.define(:bucket, :total_count, :positive_count, :rate)
    Result = Data.define(
      :candidate_count,
      :evidence_attached_count,
      :evidence_attached_rate,
      :insufficient_evidence_count,
      :average_evidence_score,
      :top_candidates,
      :adoption_rates,
      :completion_rates,
      :execution_rates
    )

    def call
      candidates = ActionCandidate.all
      evidence_candidates = candidates.select { |candidate| evidence_score(candidate).positive? }
      Result.new(
        candidate_count: candidates.count,
        evidence_attached_count: evidence_candidates.count,
        evidence_attached_rate: ratio(evidence_candidates.count, candidates.count),
        insufficient_evidence_count: candidates.count { |candidate| evidence_score(candidate) < Aicoo::EvidenceBuilder::INSUFFICIENT_SCORE },
        average_evidence_score: average(evidence_candidates.map { |candidate| evidence_score(candidate) }),
        top_candidates: candidates.sort_by { |candidate| -evidence_score(candidate) }.first(5),
        adoption_rates: rates_for(OwnerDecisionLog.last_30_days, OwnerDecisionLog::POSITIVE_DECISIONS),
        completion_rates: rates_for(OwnerDecisionLog.last_30_days, %w[complete]),
        execution_rates: rates_for(OwnerDecisionLog.last_30_days, OwnerDecisionLog::EXECUTION_DECISIONS)
      )
    end

    private

    def rates_for(logs, positive_decisions)
      %w[high medium low insufficient].map do |bucket|
        scoped = logs.select { |log| bucket_for(log.metadata.to_h.dig("evidence", "score").to_d) == bucket }
        positive = scoped.count { |log| positive_decisions.include?(log.decision_type) }
        BucketRate.new(bucket:, total_count: scoped.count, positive_count: positive, rate: ratio(positive, scoped.count))
      end
    end

    def bucket_for(score)
      return "high" if score >= 70
      return "medium" if score >= 40
      return "low" if score.positive?

      "insufficient"
    end

    def evidence_score(candidate)
      candidate.metadata.to_h.dig("evidence", "score").to_d
    end

    def average(values)
      return 0.to_d if values.empty?

      values.sum / values.size
    end

    def ratio(numerator, denominator)
      return 0.to_d if denominator.to_i.zero?

      numerator.to_d / denominator.to_d
    end
  end
end
