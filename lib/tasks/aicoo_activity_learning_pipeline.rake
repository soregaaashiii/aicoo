namespace :aicoo do
  desc "Diagnose Suelog Activity to Learning to Today E2E pipeline"
  task diagnose_activity_learning_pipeline: :environment do
    diagnostic = Aicoo::ActivityLearningPipelineDiagnostic.new(
      limit: ENV.fetch("LIMIT", 50).to_i,
      business_id: ENV["BUSINESS_ID"]
    ).call

    diagnostic.rows.each do |row|
      stage_output = row.stages.map do |stage|
        "#{stage.name}=#{stage.status}#{stage.reason.present? ? "(#{stage.reason})" : ''}"
      end.join(" ")

      puts [
        "event_id=#{row.event_id}",
        "business_id=#{row.business_id}",
        "activity_type=#{row.activity_type}",
        "source_app=#{row.source_app}",
        "received_at=#{row.received_at&.iso8601}",
        "candidate_id=#{row.candidate_id || '-'}",
        "action_result_id=#{row.action_result_id || '-'}",
        stage_output,
        "stop_reason=#{row.stop_reason || '-'}"
      ].join(" ")
    end

    summary = diagnostic.summary
    puts "summary"
    puts "activity_api_received_count=#{summary.activity_api_received_count}"
    puts "business_activity_log_count=#{summary.business_activity_log_count}"
    puts "activity_evaluation_count=#{summary.activity_evaluation_count}"
    puts "activity_to_action_result_count=#{summary.activity_to_action_result_count}"
    puts "action_result_auto_evaluated_count=#{summary.action_result_auto_evaluated_count}"
    puts "calibration_count=#{summary.calibration_count}"
    puts "learning_count=#{summary.learning_count}"
    puts "expected_value_update_count=#{summary.expected_value_update_count}"
    puts "today_reflected_count=#{summary.today_reflected_count}"
  end
end
