namespace :aicoo do
  desc "Print ActionCandidate prediction accuracy summaries"
  task judge_action_predictions: :environment do
    result = AicooJudge::ActionResultJudge.new.call

    puts "AICOO action prediction judge"
    print_summaries("generation_source", result.generation_source_summaries)
    print_summaries("business", result.business_summaries)
    print_summaries("action_type", result.action_type_summaries)
    print_summaries("metric_rule", result.metric_rule_summaries)
  end

  def print_summaries(label, summaries)
    puts "#{label}:"
    summaries.each do |summary|
      puts [
        summary.label,
        "evaluated=#{summary.evaluated_count}",
        "hit_rate=#{summary.hit_rate || 'data_shortage'}",
        "avg_error=#{summary.average_prediction_error_yen || 'data_shortage'}",
        "skipped=#{summary.skipped_count}"
      ].join(" ")
    end
  end
end
