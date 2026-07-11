namespace :aicoo do
  desc "Backfill new business candidates and exploring businesses from stored SERP results without calling SERP APIs"
  task backfill_serp_new_businesses: :environment do
    result = Aicoo::Serp::NewBusinessDiscoveryBackfiller.call

    puts "serp_runs_checked=#{result.serp_runs_checked}"
    puts "serp_analyses_checked=#{result.serp_analyses_checked}"
    puts "serp_results_checked=#{result.serp_results_checked}"
    puts "new_business_candidates_created=#{result.new_business_candidates_created}"
    puts "businesses_created=#{result.businesses_created}"
    puts "duplicates_skipped=#{result.duplicates_skipped}"
    puts "insufficient_data_skipped=#{result.insufficient_data_skipped}"
    puts "failed=#{result.failed}"
    puts "candidate_ids=#{result.candidate_ids.join(',')}"
    puts "business_ids=#{result.business_ids.join(',')}"

    if result.errors.any?
      puts "errors:"
      result.errors.each { |error| puts error.inspect }
    end
  end
end
