namespace :aicoo do
  desc "Generate ActionCandidate records from BusinessMetricDaily trends"
  task generate_action_candidates_from_metrics: :environment do
    puts "AICOO metric action candidate generation started"
    result = MetricActionCandidateGenerator.generate_all!
    puts "created_action_candidate_count=#{result.created_count}"
    puts "skipped_count=#{result.skipped_count}"
    puts "failed_count=#{result.failed_count}"
    puts "AICOO metric action candidate generation finished"
  end
end
