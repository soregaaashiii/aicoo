namespace :aicoo do
  desc "Diagnose Independent Activity Learning separately from ActionCandidate Learning"
  task diagnose_independent_activity_learning: :environment do
    result = Aicoo::IndependentActivityLearningDiagnostic.new(
      business_id: ENV["BUSINESS_ID"],
      limit: ENV.fetch("LIMIT", 1_000).to_i
    ).call

    result.rows.each do |row|
      windows = [ 7, 14, 30 ].map do |days|
        evaluation = row.evaluations[days]
        changed_metrics = evaluation.to_h.fetch("metrics", {}).filter_map do |metric, values|
          delta = values.to_h["delta"]
          "#{metric}:#{delta}" if delta.present? && delta.to_f.nonzero?
        end.first(5)
        "#{days}d=#{evaluation&.dig('status') || '-'}[#{changed_metrics.join(',')}]"
      end.join(" ")
      puts [
        "area=#{row.area || '-'}",
        "station=#{row.station || '-'}",
        "genre=#{row.genre || '-'}",
        "activity_type=#{row.activity_type}",
        "source_app=#{row.source_app}",
        "source_model=#{row.source_model}",
        "included_reason=#{row.included_reason}",
        "excluded_reason=#{row.excluded_reason || '-'}",
        "is_internal_event=#{row.is_internal_event}",
        "is_suelog_activity=#{row.is_suelog_activity}",
        "shop_count=#{row.shop_count}",
        "article_count=#{row.article_count}",
        "created_count=#{row.created_count}",
        "updated_count=#{row.updated_count}",
        "deleted_count=#{row.deleted_count}",
        "learning_status=#{row.learning_status}",
        "confidence=#{row.confidence}",
        "roi=#{row.roi || '-'}",
        windows
      ].join(" ")
    end

    result.excluded_rows.each do |row|
      puts [
        "activity_log_id=#{row.activity_log_id}",
        "activity_type=#{row.activity_type}",
        "source_app=#{row.source_app}",
        "source_model=#{row.source_model}",
        "included_reason=-",
        "excluded_reason=#{row.excluded_reason}",
        "is_internal_event=#{row.is_internal_event}",
        "is_suelog_activity=#{row.is_suelog_activity}"
      ].join(" ")
    end

    puts "summary"
    puts "activity_count=#{result.summary.activity_count}"
    puts "independent_activity_count=#{result.summary.group_count}"
    puts "pending_count=#{result.summary.pending_count}"
    puts "evaluated_count=#{result.summary.evaluated_count}"
    puts "skipped_count=#{result.summary.skipped_count}"
    puts "excluded_count=#{result.summary.excluded_count}"
    puts "excluded_reason_counts=#{result.summary.excluded_reason_counts.map { |reason, count| "#{reason}:#{count}" }.join(',')}"
  end
end
