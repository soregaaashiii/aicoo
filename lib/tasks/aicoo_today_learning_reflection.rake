namespace :aicoo do
  desc "Diagnose whether a learned ActionCandidate is reflected in Today"
  task diagnose_today_learning_reflection: :environment do
    candidate_id = ENV["CANDIDATE_ID"].presence || ActionResult.evaluated.order(id: :desc).pick(:action_candidate_id)
    abort "CANDIDATE_ID is required because no evaluated ActionResult was found" if candidate_id.blank?

    result = Aicoo::TodayLearningReflectionDiagnostic.new(candidate_id:).call
    %i[
      candidate_id business_id candidate_exists status execution_mode generation_source action_type
      total_expected_value_yen learning_applied expected_value_updated today_eligible
      today_exclusion_reason duplicate_suppressed already_executed approval_required
      included_in_candidate_items included_in_action_candidate_items included_in_ranking_input
      included_after_ranking included_in_today_board display_position final_result
    ].each do |field|
      value = result.public_send(field)
      puts "#{field}=#{value.nil? || value == '' ? '-' : value}"
    end

    result.modes.each do |mode|
      puts [
        "mode=#{mode.mode}",
        "today_eligible=#{mode.today_eligible}",
        "today_exclusion_reason=#{mode.today_exclusion_reason.presence || '-'}",
        "duplicate_suppressed=#{mode.duplicate_suppressed}",
        "already_executed=#{mode.already_executed}",
        "approval_required=#{mode.approval_required}",
        "included_in_candidate_items=#{mode.included_in_candidate_items}",
        "included_in_action_candidate_items=#{mode.included_in_action_candidate_items}",
        "included_in_ranking_input=#{mode.included_in_ranking_input}",
        "included_after_ranking=#{mode.included_after_ranking}",
        "included_in_today_board=#{mode.included_in_today_board}",
        "display_position=#{mode.display_position || '-'}",
        "final_result=#{mode.final_result}"
      ].join(" ")
    end
  end
end
