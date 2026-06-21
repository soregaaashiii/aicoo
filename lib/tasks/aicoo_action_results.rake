namespace :aicoo do
  desc "Evaluate pending ActionResult records whose evaluated_on is due"
  task evaluate_action_results: :environment do
    puts "AICOO action result evaluation started"
    results = ActionResultEvaluator.evaluate_pending!
    puts "evaluated_or_skipped_count=#{results.size}"
    puts "evaluated_count=#{results.count { |result| result.evaluation_status == 'evaluated' }}"
    puts "skipped_count=#{results.count { |result| result.evaluation_status == 'skipped' }}"
    puts "AICOO action result evaluation finished"
  end
end
