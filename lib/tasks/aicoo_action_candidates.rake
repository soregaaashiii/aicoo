namespace :aicoo do
  desc "Deduplicate equivalent ActionCandidates. Use APPLY=1 to archive duplicates and transfer related records."
  task deduplicate_action_candidates: :environment do
    apply = ENV["APPLY"].to_s.in?(%w[1 true TRUE])
    result = Aicoo::ActionCandidateDeduplicator.call(apply:)

    puts "mode=#{apply ? 'apply' : 'dry_run'}"
    puts "checked=#{result.checked}"
    puts "duplicates=#{result.duplicates}"
    puts "merged=#{result.merged}"
    puts "updated=#{result.updated}"
    puts "failed=#{result.failed}"
    puts "candidate_ids=#{result.candidate_ids.join(',')}"
  end
end
