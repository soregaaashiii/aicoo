namespace :aicoo do
  desc "Import BusinessMetricDaily from DataHub snapshots. Usage: bin/rails aicoo:import_business_metrics_daily[2026-06-21]"
  task :import_business_metrics_daily, [ :date ] => :environment do |_task, args|
    date = args[:date].present? ? Date.parse(args[:date]) : Date.yesterday
    puts "AICOO business metrics import started date=#{date}"
    results = BusinessMetricDailyImporter.import_all!(date:)
    puts "updated_business_count=#{results.size}"
    puts "AICOO business metrics import finished date=#{date}"
  rescue Date::Error => e
    warn "Invalid date: #{args[:date]} #{e.message}"
    exit 1
  end

  desc "Backfill BusinessMetricDaily for a date range. Usage: bin/rails aicoo:backfill_business_metrics_daily[2026-06-01,2026-06-21]"
  task :backfill_business_metrics_daily, [ :start_date, :end_date ] => :environment do |_task, args|
    unless args[:start_date].present? && args[:end_date].present?
      warn "start_date and end_date are required. Usage: bin/rails aicoo:backfill_business_metrics_daily[2026-06-01,2026-06-21]"
      exit 1
    end

    start_date = Date.parse(args[:start_date])
    end_date = Date.parse(args[:end_date])
    raise Date::Error, "end_date must be on or after start_date" if end_date < start_date

    puts "AICOO business metrics backfill started start_date=#{start_date} end_date=#{end_date}"
    results = BusinessMetricDailyImporter.import_all_range!(start_date:, end_date:)
    puts "updated_metric_count=#{results.size}"
    puts "AICOO business metrics backfill finished start_date=#{start_date} end_date=#{end_date}"
  rescue Date::Error => e
    warn "Invalid date range: start_date=#{args[:start_date]} end_date=#{args[:end_date]} #{e.message}"
    exit 1
  end
end
