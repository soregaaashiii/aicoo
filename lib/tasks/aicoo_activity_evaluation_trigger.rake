namespace :aicoo do
  desc "Diagnose BusinessActivityLog to ActivityEvaluationBuilder trigger coverage"
  task diagnose_activity_evaluation_trigger: :environment do
    diagnostic = Aicoo::ActivityEvaluationTriggerDiagnostic.new(
      business_id: ENV["BUSINESS_ID"],
      limit: ENV["LIMIT"]
    ).call

    diagnostic.rows.each do |row|
      puts [
        "event_id=#{row.event_id}",
        "business_id=#{row.business_id}",
        "activity_type=#{row.activity_type}",
        "builder_should_run=#{row.builder_should_run}",
        "builder_trigger_found=#{row.builder_trigger_found}",
        "builder_invoked=#{row.builder_invoked}",
        "invoked_by=#{row.invoked_by || '-'}",
        "builder_completed=#{row.builder_completed}",
        "builder_exception=#{row.builder_exception || '-'}",
        "skip_reason=#{row.skip_reason || '-'}"
      ].join(" ")
    end

    summary = diagnostic.summary
    puts "summary"
    puts "activity_count=#{summary.activity_count}"
    puts "builder_should_run_count=#{summary.builder_should_run_count}"
    puts "builder_invoked_count=#{summary.builder_invoked_count}"
    puts "builder_not_invoked_count=#{summary.builder_not_invoked_count}"
    puts "builder_completed_count=#{summary.builder_completed_count}"
    puts "builder_failed_count=#{summary.builder_failed_count}"
    puts "reason_counts=#{summary.reason_counts.map { |reason, count| "#{reason}:#{count}" }.join(',')}"
  end
end
