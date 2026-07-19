namespace :aicoo do
  desc "Evaluate pending ActionResult records whose evaluated_on is due"
  task evaluate_action_results: :environment do
    puts "AICOO action result evaluation started"
    results = ActionResultEvaluator.evaluate_pending!
    puts "evaluated_or_skipped_count=#{results.size}"
    puts "evaluated_count=#{results.count { |result| result.evaluation_status == 'evaluated' }}"
    puts "skipped_count=#{results.count { |result| result.evaluation_status == 'skipped' }}"
    puts "AICOO action result evaluation finished"
  end

  desc "Diagnose ActionResult evaluation state and exclusion reasons"
  task diagnose_action_result_evaluation: :environment do
    results = ActionResult.includes(:action_candidate, :business).order(created_at: :desc).to_a
    evaluated = results.select { |result| result.evaluation_status == "evaluated" }
    skipped = results.select { |result| result.evaluation_status == "skipped" }
    pending = results.select { |result| result.evaluation_status == "pending" }
    failed = results.select { |result| result.metadata.to_h["evaluation_error"].present? }
    excluded = pending.select { |result| result.evaluated_on && result.evaluated_on > Date.current }
    due_pending = pending - excluded
    last_evaluated = evaluated.max_by { |result| result.updated_at || result.created_at }
    last_failed = failed.max_by { |result| result.updated_at || result.created_at }

    exclusion_reasons = Hash.new(0)
    skipped.each { |result| exclusion_reasons[diagnostic_reason_for(result)] += 1 }
    excluded.each { |_result| exclusion_reasons["evaluated_on_future"] += 1 }
    due_pending.each { |_result| exclusion_reasons["pending_due_not_evaluated"] += 1 }
    failed.each { |result| exclusion_reasons[result.metadata.to_h["evaluation_error"].to_s] += 1 }

    puts "summary"
    puts "action_result_total=#{results.size}"
    puts "action_result_unevaluated=#{pending.size}"
    puts "action_result_evaluated=#{evaluated.size}"
    puts "action_result_evaluation_failed=#{failed.size}"
    puts "action_result_evaluation_skipped=#{skipped.size}"
    puts "action_result_evaluation_excluded=#{excluded.size}"
    puts "action_result_due_pending=#{due_pending.size}"
    puts "last_evaluated_action_result=#{diagnostic_action_result_line(last_evaluated)}"
    puts "last_failed_action_result=#{diagnostic_action_result_line(last_failed)}"
    puts "exclusion_reasons=#{exclusion_reasons.inspect}"

    puts "recent_action_results"
    results.first(20).each do |result|
      puts diagnostic_action_result_line(result)
    end
  end

  desc "Diagnose ActionResult manual actual fields and metadata"
  task diagnose_action_result_manual_actuals: :environment do
    results = ActionResult.includes(:action_candidate, :business).order(created_at: :desc).to_a
    recorded = results.select(&:manual_actuals_recorded?)
    not_recorded = results - recorded

    puts "summary"
    puts "action_result_total=#{results.size}"
    puts "manual_actuals_recorded_true=#{recorded.size}"
    puts "manual_actuals_recorded_false=#{not_recorded.size}"

    puts "action_results"
    results.first(50).each do |result|
      saved_fields = result.saved_manual_actual_fields
      blank_fields = manual_actual_blank_fields_for(result)
      failure_reason = manual_actual_failure_reason_for(result, saved_fields)
      puts [
        "id=#{result.id}",
        "manual_actuals_recorded=#{result.manual_actuals_recorded?}",
        "saved_actual_fields=#{saved_fields.join(',')}",
        "blank_actual_fields=#{blank_fields.join(',')}",
        "save_failure_reason=#{failure_reason}",
        "status=#{result.evaluation_status}",
        "candidate_id=#{result.action_candidate_id}",
        "business_id=#{result.business_id}",
        "action_type=#{result.action_candidate&.action_type}"
      ].join(" ")
    end
  end

  def diagnostic_reason_for(result)
    note = result.note.to_s.lines.map(&:strip).reject(&:blank?).last
    return note if note.present?

    result.evaluation_status.to_s.presence || "unknown"
  end

  def diagnostic_action_result_line(result)
    return "none" unless result

    [
      "id=#{result.id}",
      "created_at=#{result.created_at&.iso8601}",
      "status=#{result.evaluation_status}",
      "evaluated_on=#{result.evaluated_on}",
      "evaluated_at=#{result.evaluation_status == 'evaluated' ? result.updated_at&.iso8601 : nil}",
      "success=#{result.evaluation_status == 'evaluated' ? result.actual_profit_yen.to_i.positive? : nil}",
      "candidate_id=#{result.action_candidate_id}",
      "business_id=#{result.business_id}",
      "action_type=#{result.action_candidate&.action_type}",
      "manual_actuals_recorded=#{result.metadata.to_h['manual_actuals_recorded']}",
      "reason=#{diagnostic_reason_for(result)}"
    ].join(" ")
  end

  def manual_actual_blank_fields_for(result)
    column_fields = ActionResult::MANUAL_ACTUAL_FIELDS.reject do |field|
      value = result.public_send(field)
      value.respond_to?(:zero?) ? !value.zero? : value.present?
    end.map(&:to_s)
    metadata_fields = ActionResult::MANUAL_ACTUAL_METADATA_FIELDS.reject do |field|
      result.metadata.to_h.dig("manual_actuals", field).present?
    end
    column_fields + metadata_fields
  end

  def manual_actual_failure_reason_for(result, saved_fields)
    return "none" if result.manual_actuals_recorded? && saved_fields.any?
    return "manual_actuals_recorded_true_but_no_saved_actual_fields" if result.manual_actuals_recorded?
    return "saved_actual_fields_present_but_marker_false" if saved_fields.any?

    "no_manual_actual_fields_saved"
  end
end
