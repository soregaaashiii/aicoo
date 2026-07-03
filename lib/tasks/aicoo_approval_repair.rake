namespace :aicoo do
  desc "Repair approved new-business ActionCandidates that were approved before Business promotion existed"
  task repair_approved_new_business_candidates: :environment do
    scope = ActionCandidate
      .where(status: "approved")
      .where(
        "department = :department OR action_type IN (:action_types) OR generation_source IN (:sources) OR metadata ->> 'candidate_kind' = :candidate_kind",
        department: "new_business",
        action_types: Aicoo::ActionCandidateBusinessPromoter::NEW_BUSINESS_ACTION_TYPES,
        sources: Aicoo::ActionCandidateBusinessPromoter::NEW_BUSINESS_SOURCES,
        candidate_kind: "new_business"
      )

    checked = 0
    repaired = 0
    skipped = 0
    failed = 0

    scope.find_each do |candidate|
      checked += 1
      unless Aicoo::ActionCandidateBusinessPromoter.new(candidate).new_business_candidate?
        skipped += 1
        next
      end

      before_business_id = candidate.business_id
      result = Aicoo::ApprovalService.approve(
        candidate,
        operator: "system",
        source: "repair_approved_new_business_candidates"
      )
      candidate.reload

      if candidate.metadata.to_h.dig("business_promotion", "promoted") && candidate.business_id != before_business_id
        repaired += 1
        puts "repaired action_candidate_id=#{candidate.id} business_id=#{candidate.business_id} message=#{result.message}"
      elsif candidate.metadata.to_h.dig("business_promotion", "promoted")
        repaired += 1
        puts "linked action_candidate_id=#{candidate.id} business_id=#{candidate.business_id} message=#{result.message}"
      else
        skipped += 1
        puts "skipped action_candidate_id=#{candidate.id} reason=not_promoted"
      end
    rescue StandardError => e
      failed += 1
      warn "failed action_candidate_id=#{candidate.id} #{e.class}: #{e.message}"
    end

    puts "checked=#{checked} repaired=#{repaired} skipped=#{skipped} failed=#{failed}"
    exit(1) if failed.positive?
  end
end
