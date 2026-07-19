namespace :aicoo do
  desc "Diagnose BusinessActivityLog creation paths and callback coverage"
  task diagnose_business_activity_log_creation: :environment do
    diagnostic = Aicoo::BusinessActivityLogCreationDiagnostic.new(
      business_id: ENV["BUSINESS_ID"],
      limit: ENV["LIMIT"]
    ).call

    diagnostic.rows.each do |row|
      puts [
        "event_id=#{row.event_id}",
        "created_by_method=#{row.created_by_method}",
        "created_by_file=#{row.created_by_file || '-'}",
        "created_by_line=#{row.created_by_line || '-'}",
        "persistence_method=#{row.persistence_method}",
        "active_record_callbacks_enabled=#{row.active_record_callbacks_enabled.nil? ? '-' : row.active_record_callbacks_enabled}",
        "after_create_called=#{row.after_create_called}",
        "after_commit_called=#{row.after_commit_called}",
        "callback_skipped_reason=#{row.callback_skipped_reason || '-'}",
        "trigger_registered=#{row.trigger_registered}",
        "trigger_called=#{row.trigger_called}",
        "builder_called=#{row.builder_called}"
      ].join(" ")
    end

    summary = diagnostic.summary
    puts "summary"
    puts "record_count=#{summary.record_count}"
    puts "after_create_called_count=#{summary.after_create_called_count}"
    puts "after_commit_count=#{summary.after_commit_count}"
    puts "callback_executed_count=#{summary.callback_executed_count}"
    puts "callback_not_executed_count=#{summary.callback_not_executed_count}"
    puts "trigger_registered_count=#{summary.trigger_registered_count}"
    puts "trigger_called_count=#{summary.trigger_called_count}"
    puts "builder_called_count=#{summary.builder_called_count}"
    puts "creation_path_counts=#{summary.creation_path_counts.map { |path, count| "#{path}=#{count}" }.join(',')}"
    puts "callback_skip_reason_counts=#{summary.callback_skip_reason_counts.map { |reason, count| "#{reason}:#{count}" }.join(',')}"
  end
end
