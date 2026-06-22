class MetaEvaluationSnapshotter
  Result = Data.define(:snapshots, :created_count, :top_evaluator, :confidence_by_type) do
    def count
      snapshots.size
    end
  end

  def snapshot!(date: Date.current, aicoo_daily_run: nil)
    snapshots = []
    snapshots.concat(snapshot_scope!(scope: ActionCandidate.active_for_ranking.includes(:business), date:, aicoo_daily_run:, business: nil))
    Business.find_each do |business|
      snapshots.concat(snapshot_business!(business:, date:, aicoo_daily_run:))
    end

    global_snapshots = snapshots.select { |snapshot| snapshot.business_id.nil? }
    Result.new(
      snapshots:,
      created_count: snapshots.count(&:previously_new_record?),
      top_evaluator: global_snapshots.max_by(&:average_confidence_score)&.evaluator_type,
      confidence_by_type: confidence_map(global_snapshots)
    )
  end

  def snapshot_business!(business:, date: Date.current, aicoo_daily_run: nil)
    snapshot_scope!(
      scope: business.action_candidates.active_for_ranking,
      date:,
      aicoo_daily_run:,
      business:
    )
  end

  private

  def snapshot_scope!(scope:, date:, aicoo_daily_run:, business:)
    grouped_breakdowns(scope).map do |evaluator_type, entries|
      persist_snapshot!(
        evaluator_type:,
        entries:,
        date:,
        aicoo_daily_run:,
        business:
      )
    end
  end

  def grouped_breakdowns(scope)
    grouped = Hash.new { |hash, key| hash[key] = [] }
    scope.find_each do |candidate|
      candidate.metadata.to_h.fetch("evaluator_breakdown", []).each do |entry|
        evaluator_type = entry["evaluator_type"].to_s
        next unless MetaEvaluationSnapshot::EVALUATOR_TYPES.include?(evaluator_type)

        grouped[evaluator_type] << entry
      end
    end
    MetaEvaluationSnapshot::EVALUATOR_TYPES.index_with { |type| grouped[type] }
  end

  def persist_snapshot!(evaluator_type:, entries:, date:, aicoo_daily_run:, business:)
    snapshot = MetaEvaluationSnapshot.find_or_initialize_by(
      recorded_on: date,
      business:,
      evaluator_type:
    )
    average_expected_value = average(entries.map { |entry| entry["expected_value_yen"].to_i })
    average_confidence = average(entries.map { |entry| entry["confidence_score"].to_i })
    snapshot.assign_attributes(
      aicoo_daily_run:,
      average_expected_value_yen: average_expected_value.round,
      average_confidence_score: average_confidence,
      candidate_count: entries.size,
      weighted_contribution_score: average_expected_value * (average_confidence / 100),
      note: note_for(evaluator_type, entries.size)
    )
    snapshot.save!
    snapshot
  end

  def confidence_map(snapshots)
    MetaEvaluationSnapshot::EVALUATOR_TYPES.index_with do |type|
      snapshots.find { |snapshot| snapshot.evaluator_type == type }&.average_confidence_score.to_d
    end
  end

  def average(values)
    return 0.to_d if values.empty?

    values.map(&:to_d).sum / values.size
  end

  def note_for(evaluator_type, count)
    return "#{evaluator_type} の評価内訳がありません。" if count.zero?

    "#{evaluator_type} の評価内訳を#{count}件集計しました。"
  end
end
