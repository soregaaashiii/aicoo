class DataPreparationExecutorQueuer
  Result = Data.define(:candidate_count, :queued_count, :skipped_count, :skipped_reasons, :disabled)

  def initialize(force: false)
    @force = force
    @skipped_reasons = Hash.new(0)
  end

  def call
    return disabled_result unless enabled?

    queued_count = 0
    candidates.find_each do |candidate|
      if AicooExecutorTask.unfinished_for_action_candidate(candidate)
        skipped_reasons["already queued"] += 1
        next
      end

      AicooExecutor::TaskBuilder.from_action_candidate(candidate)
      queued_count += 1
    end

    Result.new(
      candidate_count: candidates.count,
      queued_count:,
      skipped_count: candidates.count - queued_count,
      skipped_reasons:,
      disabled: false
    )
  end

  private

  attr_reader :force, :skipped_reasons

  def enabled?
    force || AicooSetting.current.auto_queue_data_preparation_tasks?
  end

  def disabled_result
    Result.new(
      candidate_count: candidates.count,
      queued_count: 0,
      skipped_count: candidates.count,
      skipped_reasons: { "auto queue disabled" => candidates.count },
      disabled: true
    )
  end

  def candidates
    @candidates ||= ActionCandidate.active_for_ranking
                                   .where(action_type: "data_preparation", status: "idea")
  end
end
