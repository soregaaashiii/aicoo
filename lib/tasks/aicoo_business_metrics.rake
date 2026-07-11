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

  desc "Diagnose BusinessMetricDaily import without running full Daily Run. Usage: bin/rails aicoo:diagnose_business_metrics_import TARGET_DATE=2026-07-10"
  task diagnose_business_metrics_import: :environment do
    date = Date.parse(ENV.fetch("TARGET_DATE", Date.yesterday.to_s))
    range = date.beginning_of_day..(date.end_of_day + BusinessMetricDailyImporter::SNAPSHOT_LOOKAHEAD)
    source_scope = AicooDataSnapshot.where(source_type: %w[gsc ga4 landing_page], captured_at: range)
    existing_metric_count = BusinessMetricDaily.where(recorded_on: date).count
    target_business_count = Business.real_businesses.count
    locked_steps = AicooDailyRunStep.joins(:aicoo_daily_run)
                                    .where(step_name: "business_metrics_import", status: "running")
                                    .where(aicoo_daily_runs: { status: "running" })
    businesses_with_source = source_scope
      .where("payload ? 'business_id'")
      .pluck(Arel.sql("DISTINCT (payload ->> 'business_id')"))
      .compact
      .map(&:to_i)
    missing_source_count = [ target_business_count - businesses_with_source.uniq.size, 0 ].max

    puts "target_date=#{date}"
    puts "target_business_count=#{target_business_count}"
    puts "source_record_count=#{source_scope.count}"
    puts "existing_metric_count=#{existing_metric_count}"
    puts "estimated_work=businesses=#{target_business_count} snapshots=#{source_scope.count}"
    puts "last_successful_import_at=#{BusinessMetricDaily.maximum(:updated_at)&.iso8601 || '-'}"
    puts "currently_locked=#{locked_steps.exists?}"
    puts "locked_run_ids=#{locked_steps.pluck(:aicoo_daily_run_id).join(',')}"
    puts "suspected_blocker=#{locked_steps.exists? ? 'business_metrics_import_running' : 'none'}"
    puts "businesses_with_missing_source=#{missing_source_count}"
    large_volume_businesses = source_scope
      .group(Arel.sql("payload ->> 'business_id'"))
      .count
      .select { |_id, count| count > 100 }
      .first(10)
    puts "businesses_with_large_volume=#{large_volume_businesses.inspect}"
  rescue Date::Error => e
    warn "Invalid target date: #{e.message}"
    exit 1
  end

  desc "Run only BusinessMetricDaily import. Usage: bin/rails aicoo:run_business_metrics_import TARGET_DATE=2026-07-10"
  task run_business_metrics_import: :environment do
    date = Date.parse(ENV.fetch("TARGET_DATE", Date.yesterday.to_s))
    started_at = Time.current
    puts "business_metrics_import start target_date=#{date}"
    results = BusinessMetricDailyImporter.import_all!(
      date:,
      progress: lambda { |progress|
        puts [
          "progress",
          "event=#{progress.event}",
          "processed=#{progress.processed_business_count}/#{progress.target_business_count}",
          "business_id=#{progress.current_business_id || '-'}",
          "created=#{progress.created_count}",
          "updated=#{progress.updated_count}",
          "skipped=#{progress.skipped_count}",
          "errors=#{progress.error_count}",
          "elapsed=#{progress.elapsed_seconds.to_f.round(1)}s"
        ].join(" ")
      }
    )
    puts "business_metrics_import finish target_date=#{date} updated_business_count=#{results.size} elapsed=#{(Time.current - started_at).round(1)}s"
  rescue Date::Error => e
    warn "Invalid target date: #{e.message}"
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
