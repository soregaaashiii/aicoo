namespace :aicoo do
  desc "Diagnose Independent Learning to ActionCandidate generation"
  task diagnose_independent_candidate_generation: :environment do
    apply = ENV["APPLY"].to_s == "1"
    result = Aicoo::IndependentActivityCandidateGenerator.call(
      business_id: ENV["BUSINESS_ID"],
      apply:,
      limit: ENV.fetch("LIMIT", 5_000).to_i
    )

    puts "mode=#{apply ? 'apply' : 'dry-run'}"
    result.rows.each do |row|
      puts [
        "learning_id=#{row.learning_id}",
        "business_id=#{row.business_id}",
        "activity_type=#{row.activity_type}",
        "area=#{row.area || '-'}",
        "genre=#{row.genre || '-'}",
        "smoking=#{row.smoking_type || '-'}",
        "roi=#{row.roi || '-'}",
        "confidence=#{row.confidence}",
        "sample_count=#{row.sample_count}",
        "candidate_generated=#{row.candidate_generated}",
        "candidate_id=#{row.candidate_id || '-'}",
        "duplicate=#{row.duplicate}",
        "skip_reason=#{row.skip_reason || '-'}"
      ].join(" ")
    end

    puts "summary"
    puts "learning_count=#{result.summary.learning_count}"
    puts "eligible_learning_count=#{result.summary.eligible_count}"
    puts "generated_count=#{result.summary.generated_count}"
    puts "duplicate_count=#{result.summary.duplicate_count}"
    puts "rejected_count=#{result.summary.rejected_count}"
    puts "reason_counts=#{result.summary.reason_counts.map { |reason, count| "#{reason}:#{count}" }.join(',')}"
  end
end
