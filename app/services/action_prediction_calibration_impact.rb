class ActionPredictionCalibrationImpact
  Result = Data.define(
    :rank_up,
    :rank_down,
    :entered_top10,
    :left_top10,
    :action_type_changes,
    :changed_count,
    :largest_rank_up,
    :largest_rank_down
  )
  Row = Data.define(
    :action_candidate,
    :raw_expected_profit_yen,
    :adjusted_expected_profit_yen,
    :raw_success_probability,
    :adjusted_success_probability,
    :raw_score,
    :adjusted_score,
    :raw_rank,
    :adjusted_rank
  ) do
    def score_delta
      adjusted_score.to_d - raw_score.to_d
    end

    def rank_delta
      raw_rank.to_i - adjusted_rank.to_i
    end

    def changed?
      rank_delta != 0 || score_delta != 0
    end
  end
  ActionTypeChange = Data.define(:action_type, :candidate_count, :average_score_delta)

  def initialize(scope: ActionCandidate.active_for_ranking)
    @scope = scope
  end

  def call(limit: 10)
    rows = ranked_rows
    Result.new(
      rank_up: rows.select { |row| row.rank_delta.positive? }.sort_by { |row| -row.rank_delta }.first(limit),
      rank_down: rows.select { |row| row.rank_delta.negative? }.sort_by(&:rank_delta).first(limit),
      entered_top10: rows.select { |row| row.raw_rank > 10 && row.adjusted_rank <= 10 }.sort_by(&:adjusted_rank),
      left_top10: rows.select { |row| row.raw_rank <= 10 && row.adjusted_rank > 10 }.sort_by(&:raw_rank),
      action_type_changes: action_type_changes(rows),
      changed_count: rows.count(&:changed?),
      largest_rank_up: rows.select { |row| row.rank_delta.positive? }.max_by(&:rank_delta),
      largest_rank_down: rows.select { |row| row.rank_delta.negative? }.min_by(&:rank_delta)
    )
  end

  private

  attr_reader :scope

  def ranked_rows
    candidates = scope.includes(:business).to_a
    raw_rank_by_id = rank_by(candidates) { |candidate| raw_score(candidate) }
    adjusted_rank_by_id = rank_by(candidates) { |candidate| adjusted_score(candidate) }

    candidates.map do |candidate|
      Row.new(
        action_candidate: candidate,
        raw_expected_profit_yen: raw_expected_profit(candidate),
        adjusted_expected_profit_yen: candidate.expected_profit_yen.to_i,
        raw_success_probability: candidate.success_probability.to_d,
        adjusted_success_probability: adjusted_success_probability(candidate),
        raw_score: raw_score(candidate),
        adjusted_score: adjusted_score(candidate),
        raw_rank: raw_rank_by_id.fetch(candidate.id),
        adjusted_rank: adjusted_rank_by_id.fetch(candidate.id)
      )
    end
  end

  def rank_by(candidates)
    candidates.sort_by { |candidate| [ -yield(candidate).to_d, candidate.title.to_s, candidate.id.to_i ] }
              .each_with_index
              .to_h { |candidate, index| [ candidate.id, index + 1 ] }
  end

  def raw_score(candidate)
    hourly_value =
      if candidate.expected_hours.to_d.positive?
        raw_expected_profit(candidate).to_d / candidate.expected_hours.to_d
      else
        0.to_d
      end
    strategic_value = candidate.strategic_value_score.to_i * 100
    risk_reduction_value = candidate.risk_reduction_score.to_i * 100
    (hourly_value * 0.7) + (strategic_value * 0.2) + (risk_reduction_value * 0.1)
  end

  def adjusted_score(candidate)
    candidate.final_score.to_d
  end

  def raw_expected_profit(candidate)
    metadata_value(candidate, "raw_expected_profit_yen") || (candidate.immediate_value_yen.to_d * candidate.success_probability.to_d).round
  end

  def adjusted_success_probability(candidate)
    value = metadata_value(candidate, "adjusted_success_probability")
    return value.to_d if value

    candidate.calibrated_success_probability
  end

  def metadata_value(candidate, key)
    value = candidate.metadata.to_h.dig("prediction_calibration", key)
    return nil if value.blank?

    value.to_d
  end

  def action_type_changes(rows)
    rows.group_by { |row| row.action_candidate.action_type }.map do |action_type, grouped_rows|
      average = grouped_rows.sum(&:score_delta).to_d / grouped_rows.size
      ActionTypeChange.new(action_type:, candidate_count: grouped_rows.size, average_score_delta: average)
    end.sort_by { |change| [ -change.average_score_delta.abs, change.action_type.to_s ] }
  end
end
