namespace :aicoo do
  desc "Diagnose improvement event entry into BusinessActivityLog"
  task diagnose_activity_event_entry: :environment do
    diagnostic = Aicoo::ActivityEventEntryDiagnostic.new(business_id: ENV["BUSINESS_ID"]).call

    diagnostic.rows.each do |row|
      puts [
        "event_type=#{row.event_type}",
        "model=#{row.model}",
        "record_saved=#{row.record_saved}",
        "callback_called=#{row.callback_called}",
        "activity_log_record_called=#{row.activity_log_record_called}",
        "business_activity_log_created=#{row.business_activity_log_created}",
        "activity_api_sent=#{row.activity_api_sent}",
        "skip_reason=#{row.skip_reason || '-'}",
        "exception=#{row.exception || '-'}"
      ].join(" ")
    end

    summary = diagnostic.summary
    puts "summary"
    puts "shop_create_count=#{summary.shop_create_count}"
    puts "shop_update_count=#{summary.shop_update_count}"
    puts "article_create_count=#{summary.article_create_count}"
    puts "article_update_count=#{summary.article_update_count}"
    puts "record_call_count=#{summary.record_call_count}"
    puts "business_activity_log_count=#{summary.business_activity_log_count}"
    puts "activity_api_count=#{summary.activity_api_count}"
    puts "db_diff_count=#{summary.db_diff_count}"
    puts "source_database_configured=#{summary.source_database_configured}"
    puts "source_database_available=#{summary.source_database_available}"
    puts "activity_api_token_configured=#{summary.activity_api_token_configured}"
    puts "diff_connection_enabled=#{summary.diff_connection_enabled}"
    puts "reason_counts=#{summary.reason_counts.map { |reason, count| "#{reason}:#{count}" }.join(',')}"
  end
end
