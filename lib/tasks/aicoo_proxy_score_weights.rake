namespace :aicoo do
  desc "Adjust proxy_score weights. Usage: bin/rails aicoo:adjust_proxy_score_weights[2026-06-01,2026-06-21]"
  task :adjust_proxy_score_weights, [ :start_date, :end_date ] => :environment do |_task, args|
    start_date = args[:start_date].present? ? Date.parse(args[:start_date]) : 30.days.ago.to_date
    end_date = args[:end_date].present? ? Date.parse(args[:end_date]) : Date.current
    raise Date::Error, "end_date must be on or after start_date" if end_date < start_date

    puts "AICOO proxy_score weight adjustment started start_date=#{start_date} end_date=#{end_date}"
    adjuster = ProxyScoreWeightAdjuster.new
    business_logs = adjuster.adjust_all_businesses!(start_date:, end_date:)
    global_log = adjuster.adjust_global!(start_date:, end_date:)
    puts "business_adjustment_log_count=#{business_logs.size}"
    puts "global_adjustment_reason=#{global_log.reason}"
    puts "AICOO proxy_score weight adjustment finished start_date=#{start_date} end_date=#{end_date}"
  rescue Date::Error => e
    warn "Invalid date range: start_date=#{args[:start_date]} end_date=#{args[:end_date]} #{e.message}"
    exit 1
  end
end
