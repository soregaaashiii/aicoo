class ActionCandidateScoreSnapshotter
  Result = Data.define(:snapshots, :created_count, :rank_up_count, :rank_down_count, :no_adjustment_count)

  def snapshot!(date: Date.current)
    snapshot_candidates!(candidates: active_candidates, date:)
  end

  def snapshot_top_candidates!(date: Date.current, limit: 50)
    scored_candidates = scored_candidates(active_candidates)
    selected_candidates = scored_candidates
      .sort_by { |score| [ -score.judge_adjusted_score.to_d, -score.base_score.to_d ] }
      .first(limit)
      .map(&:action_candidate)

    snapshot_candidates!(candidates: selected_candidates, date:)
  end

  private

  def snapshot_candidates!(candidates:, date:)
    date = date.to_date
    candidates = candidates.to_a
    score_map = score_builder.score_map(candidates)
    raw_ranks = ranks_for(candidates, score_map) { |action_candidate, score| [ -score.base_score.to_d, -action_candidate.expected_profit_yen.to_i ] }
    adjusted_ranks = ranks_for(candidates, score_map) { |action_candidate, score| [ -score.judge_adjusted_score.to_d, -action_candidate.expected_profit_yen.to_i ] }

    created_count = 0
    snapshots = candidates.map do |action_candidate|
      score = score_map.fetch(action_candidate)
      snapshot = ActionCandidateScoreSnapshot.find_or_initialize_by(action_candidate:, recorded_on: date)
      created_count += 1 if snapshot.new_record?
      snapshot.assign_attributes(snapshot_attributes(action_candidate, score, raw_ranks, adjusted_ranks))
      snapshot.save!
      snapshot
    end

    Result.new(
      snapshots:,
      created_count:,
      rank_up_count: snapshots.count { |snapshot| snapshot.rank_delta.positive? },
      rank_down_count: snapshots.count { |snapshot| snapshot.rank_delta.negative? },
      no_adjustment_count: snapshots.count { |snapshot| no_adjustment?(snapshot) }
    )
  end

  def snapshot_attributes(action_candidate, score, raw_ranks, adjusted_ranks)
    raw_rank = raw_ranks.fetch(action_candidate.id)
    adjusted_rank = adjusted_ranks.fetch(action_candidate.id)
    rank_delta = raw_rank - adjusted_rank

    {
      business: action_candidate.business,
      raw_score: score.base_score,
      judge_adjusted_score: score.judge_adjusted_score,
      generation_source_accuracy: score.generation_source_accuracy,
      action_type_accuracy: score.action_type_accuracy,
      business_error_rate: score.business_average_prediction_error_rate,
      adjustment_multiplier: score.multiplier,
      raw_rank:,
      adjusted_rank:,
      rank_delta:,
      reason: reason_for(score, rank_delta)
    }
  end

  def ranks_for(candidates, score_map)
    candidates
      .sort_by { |action_candidate| yield(action_candidate, score_map.fetch(action_candidate)) }
      .each_with_index
      .to_h { |action_candidate, index| [ action_candidate.id, index + 1 ] }
  end

  def reason_for(score, rank_delta)
    return "データ不足で補正なし" if score.generation_source_accuracy.nil? && score.action_type_accuracy.nil?
    return "Judge補正で順位上昇" if rank_delta.positive?
    return "Judge補正で順位低下" if rank_delta.negative?
    return "action_type精度不足で低下" if score.action_type_accuracy.to_d < 0.5
    return "generation_source精度不足で低下" if score.generation_source_accuracy.to_d < 0.5

    "補正影響なし"
  end

  def no_adjustment?(snapshot)
    snapshot.adjustment_multiplier.to_d == 1.to_d &&
      snapshot.generation_source_accuracy.nil? &&
      snapshot.action_type_accuracy.nil?
  end

  def scored_candidates(candidates)
    score_builder.score_map(candidates).values
  end

  def active_candidates
    ActionCandidate.active_for_ranking.includes(:business)
  end

  def score_builder
    @score_builder ||= AicooJudge::ActionCandidateScore.new
  end
end
