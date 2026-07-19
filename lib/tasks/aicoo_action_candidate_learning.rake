namespace :aicoo do
  desc "Diagnose ActionCandidate Learning without Independent Activity Learning"
  task diagnose_action_candidate_learning: :environment do
    result = Aicoo::ActionCandidateLearningDiagnostic.new(
      business_id: ENV["BUSINESS_ID"],
      limit: ENV.fetch("LIMIT", 500).to_i
    ).call

    result.rows.each do |row|
      puts [
        "candidate_id=#{row.candidate_id}",
        "registered_count=#{row.registered_count || '-'}",
        "action_result_id=#{row.action_result_id}",
        "action_result_status=#{row.action_result_status}",
        "learning=#{row.learning_available ? 'available' : 'unavailable'}",
        "calibration_id=#{row.calibration_id || '-'}",
        "expected_value_yen=#{row.expected_value_yen}"
      ].join(" ")
    end

    puts "summary"
    puts "action_candidate_count=#{result.candidate_count}"
    puts "evaluated_count=#{result.evaluated_count}"
    puts "learning_count=#{result.learning_count}"
  end
end
