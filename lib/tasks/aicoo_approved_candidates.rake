namespace :aicoo do
  desc "Queue approved ActionCandidates into Executor approval_pending"
  task queue_approved_candidates: :environment do
    result = AicooExecutor::ApprovedCandidateQueuer.queue_all!

    puts "AICOO queue approved candidates"
    puts "target_count=#{result.target_count}"
    puts "created_count=#{result.created_count}"
    puts "skipped_count=#{result.skipped_count}"
    puts "reasons=#{result.skipped_reasons.map { |reason, count| "#{reason}=#{count}" }.join(', ')}"
  end
end
