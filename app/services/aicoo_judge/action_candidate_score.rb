module AicooJudge
  class ActionCandidateScore
    Score = Data.define(
      :action_candidate,
      :base_score,
      :generation_source_accuracy,
      :action_type_accuracy,
      :business_average_prediction_error_rate,
      :multiplier,
      :judge_adjusted_score
    )

    MIN_MULTIPLIER = 0.5.to_d
    MAX_MULTIPLIER = 2.to_d

    def initialize(start_date: 30.days.ago.to_date, end_date: Date.current)
      @judge_result = ActionResultJudge.new(start_date:, end_date:).call
    end

    def score_for(action_candidate)
      generation_source_accuracy = hit_rate_for(judge_result.generation_source_summaries, action_candidate.generation_source)
      action_type_accuracy = hit_rate_for(judge_result.action_type_summaries, action_candidate.action_type)
      business_summary = summary_for(judge_result.business_summaries, action_candidate.business.name)
      multiplier = accuracy_multiplier(generation_source_accuracy, action_type_accuracy)
      base_score = action_candidate.final_score.to_d

      Score.new(
        action_candidate:,
        base_score:,
        generation_source_accuracy:,
        action_type_accuracy:,
        business_average_prediction_error_rate: business_summary&.average_prediction_error_rate,
        multiplier:,
        judge_adjusted_score: base_score * multiplier
      )
    end

    def score_map(action_candidates)
      action_candidates.index_with { |action_candidate| score_for(action_candidate) }
    end

    private

    attr_reader :judge_result

    def hit_rate_for(summaries, label)
      summary_for(summaries, label)&.hit_rate
    end

    def summary_for(summaries, label)
      summaries.find { |summary| summary.label == label }
    end

    def accuracy_multiplier(generation_source_accuracy, action_type_accuracy)
      raw_multiplier = [
        generation_source_accuracy || 1,
        action_type_accuracy || 1
      ].map(&:to_d).inject(:*)

      raw_multiplier.clamp(MIN_MULTIPLIER, MAX_MULTIPLIER)
    end
  end
end
