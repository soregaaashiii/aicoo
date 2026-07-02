namespace :aicoo do
  desc "Create AutoRevisionTasks for approved ActionCandidates"
  task queue_approved_candidates: :environment do
    result = AicooExecutor::ApprovedCandidateQueuer.queue_all!

    puts "AICOO create auto revision tasks from approved candidates"
    puts "target_count=#{result.target_count}"
    puts "created_count=#{result.created_count}"
    puts "skipped_count=#{result.skipped_count}"
    puts "reasons=#{result.skipped_reasons.map { |reason, count| "#{reason}=#{count}" }.join(', ')}"
  end
end
