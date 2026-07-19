namespace :aicoo do
  desc "Diagnose BusinessActivityLog to ActivityEvaluation builder coverage"
  task diagnose_activity_evaluation_builder: :environment do
    diagnostic = Aicoo::ActivityEvaluationBuilderDiagnostic.new(
      business_id: ENV["BUSINESS_ID"],
      limit: ENV["LIMIT"]
    ).call

    diagnostic.rows.each do |row|
      puts [
        "event_id=#{row.event_id}",
        "activity_type=#{row.activity_type}",
        "business_id=#{row.business_id}",
        "received_at=#{row.received_at&.iso8601}",
        "result=#{row.result}",
        "evaluation_target=#{row.eligible}",
        "eligibility_reason=#{row.eligibility_reason}",
        "evaluation_status=#{row.evaluation_status}",
        "evaluation_generated=#{row.evaluation_generated}",
        "evaluation_windows=#{row.evaluation_windows.join(',')}",
        "missing_windows=#{row.missing_windows.join(',')}",
        "due_windows=#{row.due_windows.join(',')}",
        "pending_windows=#{row.pending_windows.join(',')}",
        "excluded_reason=#{row.excluded_reason || '-'}",
        "evaluation_missing_reason=#{row.missing_reason || '-'}"
      ].join(" ")
    end

    summary = diagnostic.summary
    puts "summary"
    puts "activity_count=#{summary.activity_count}"
    puts "eligible_count=#{summary.eligible_count}"
    puts "excluded_count=#{summary.excluded_count}"
    puts "evaluation_generated_count=#{summary.evaluation_generated_count}"
    puts "generation_failed_count=#{summary.generation_failed_count}"
    puts "evaluation_record_count=#{summary.evaluation_record_count}"
    puts "reason_counts=#{summary.reason_counts.map { |reason, count| "#{reason}:#{count}" }.join(',')}"
  end
end
