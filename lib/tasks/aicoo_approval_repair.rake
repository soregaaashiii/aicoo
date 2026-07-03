namespace :aicoo do
  desc "Repair approved new-business ActionCandidates that were approved before Business promotion existed"
  task repair_approved_new_business_candidates: :environment do
    result = Aicoo::ApprovedNewBusinessCandidateRepairer.call(source: "repair_approved_new_business_candidates")
    result.errors.each do |error|
      warn "failed action_candidate_id=#{error[:action_candidate_id]} #{error[:error_class]}: #{error[:message]}"
    end
    puts "checked=#{result.checked_count} repaired=#{result.repaired_count} skipped=#{result.skipped_count} failed=#{result.failed_count}"
    exit(1) if result.failed_count.positive?
  end
end
