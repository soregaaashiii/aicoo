namespace :aicoo do
  desc "Repair TodayActionBoard eligibility metadata. Use APPLY=1 to write exclusions."
  task repair_today_action_eligibility: :environment do
    result = Aicoo::TodayActionEligibilityRepair.call(apply: ENV["APPLY"] == "1")

    puts "checked=#{result.checked}"
    puts "external_url_excluded=#{result.external_url_excluded}"
    puts "invalid_path_excluded=#{result.invalid_path_excluded}"
    puts "unrealistic_profit_excluded=#{result.unrealistic_profit_excluded}"
    puts "duplicate_grouped=#{result.duplicate_grouped}"
    puts "exploring_not_actionable=#{result.exploring_not_actionable}"
    puts "eligible=#{result.eligible}"
    puts "failed=#{result.failed}"
    puts "applied=#{result.applied}"
  end
end
