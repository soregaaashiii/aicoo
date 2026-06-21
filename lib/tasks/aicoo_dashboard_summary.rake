namespace :aicoo do
  desc "Print AICOO dashboard summary"
  task dashboard_summary: :environment do
    summary = DashboardSummaryService.new.call
    today = summary.today
    judge = summary.judge

    puts "AICOO dashboard summary"
    puts "Daily Run: status=#{today.status} target_date=#{today.target_date} started_at=#{today.started_at || '-'}"
    puts "Daily Run counts: action_candidates=#{today.action_candidates_generated_count} action_results=#{today.action_results_evaluated_count}"
    puts "Revenue: revenue_yen=#{today.revenue_total_yen} profit_yen=#{today.profit_total_yen}"
    puts "Proxy score change: #{today.proxy_score_change_rate || 'data_shortage'}"
    puts "Judge: evaluated=#{judge.summary.evaluated_count} hit_rate=#{judge.summary.hit_rate || 'data_shortage'}"
    puts "Top Business: #{summary.top_business&.label || 'data_shortage'}"
    puts "Top Generation Source: #{summary.top_generation_source&.label || 'data_shortage'}"
  end
end
