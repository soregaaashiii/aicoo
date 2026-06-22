namespace :aicoo do
  desc "Snapshot MetaEvaluator weights for ActionCandidates"
  task :snapshot_meta_evaluations, [ :date ] => :environment do |_task, args|
    date = args[:date].present? ? Date.parse(args[:date]) : Date.current
    result = MetaEvaluationSnapshotter.new.snapshot!(date:)

    puts "AICOO MetaEvaluator snapshot"
    puts "recorded_on=#{date}"
    puts "created_count=#{result.created_count}"
    puts "top_evaluator=#{result.top_evaluator || 'none'}"
    result.confidence_by_type.each do |evaluator_type, confidence|
      puts "#{evaluator_type}_average_confidence=#{confidence.round(1)}"
    end
  rescue Date::Error
    abort "Invalid date. Use YYYY-MM-DD."
  end
end
