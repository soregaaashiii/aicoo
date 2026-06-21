namespace :aicoo do
  desc "Queue data_preparation ActionCandidates into Executor approval_pending"
  task auto_queue_data_preparation: :environment do
    result = DataPreparationExecutorQueuer.new(force: true).call

    puts "AICOO data_preparation auto queue"
    puts "data_preparation_candidates_count=#{result.candidate_count}"
    puts "data_preparation_auto_queued_count=#{result.queued_count}"
    puts "skipped_count=#{result.skipped_count}"
    puts "reasons=#{result.skipped_reasons.map { |reason, count| "#{reason}=#{count}" }.join(', ')}"
  end
end
