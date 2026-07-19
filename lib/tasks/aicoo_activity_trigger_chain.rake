namespace :aicoo do
  desc "Diagnose BusinessActivityLog after-commit trigger chain"
  task diagnose_activity_trigger_chain: :environment do
    diagnostic = Aicoo::ActivityTriggerChainDiagnostic.new(
      business_id: ENV["BUSINESS_ID"],
      limit: ENV["LIMIT"]
    ).call

    diagnostic.rows.each do |row|
      puts [
        "event_id=#{row.event_id}",
        "activity_type=#{row.activity_type}",
        "business_id=#{row.business_id}",
        "record_created=#{row.record_created}",
        "after_create_called=#{row.after_create_called}",
        "after_commit_called=#{row.after_commit_called}",
        "after_commit_skipped=#{row.after_commit_skipped}",
        "trigger_registered=#{row.trigger_registered}",
        "trigger_called=#{row.trigger_called}",
        "trigger_completed=#{row.trigger_completed}",
        "builder_called=#{row.builder_called}",
        "builder_completed=#{row.builder_completed}",
        "return_point=#{row.return_point}",
        "exception=#{row.exception || '-'}",
        "skip_reason=#{row.skip_reason || '-'}"
      ].join(" ")
    end

    summary = diagnostic.summary
    puts "summary"
    puts "record_count=#{summary.record_count}"
    puts "after_commit_count=#{summary.after_commit_count}"
    puts "trigger_registered_count=#{summary.trigger_registered_count}"
    puts "trigger_called_count=#{summary.trigger_called_count}"
    puts "builder_called_count=#{summary.builder_called_count}"
    puts "builder_completed_count=#{summary.builder_completed_count}"
    puts "reason_counts=#{summary.reason_counts.map { |reason, count| "#{reason}:#{count}" }.join(',')}"
  end
end
