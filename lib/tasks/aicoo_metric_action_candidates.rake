namespace :aicoo do
  desc "Generate ActionCandidate records from BusinessMetricDaily trends"
  task generate_action_candidates_from_metrics: :environment do
    puts "AICOO metric action candidate generation started"
    results = MetricActionCandidateGenerator.generate_all!
    created_count = results.sum(&:created_count)
    skipped_count = results.sum { |result| result.skipped.size }
    puts "created_action_candidate_count=#{created_count}"
    puts "skipped_count=#{skipped_count}"
    puts "AICOO metric action candidate generation finished"
  end
end
