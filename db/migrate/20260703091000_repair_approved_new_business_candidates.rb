class RepairApprovedNewBusinessCandidates < ActiveRecord::Migration[8.1]
  def up
    return unless table_exists?(:action_candidates) && table_exists?(:businesses)

    ActionCandidate.reset_column_information
    Business.reset_column_information

    checked = 0
    repaired = 0
    skipped = 0
    failed = 0

    approved_new_business_candidates.find_each do |candidate|
      checked += 1
      promoter = Aicoo::ActionCandidateBusinessPromoter.new(candidate)

      unless promoter.new_business_candidate?
        skipped += 1
        next
      end

      if already_promoted?(candidate)
        skipped += 1
        next
      end

      Aicoo::ApprovalService.approve(
        candidate,
        operator: "system",
        source: "migration_repair_approved_new_business_candidates"
      )
      repaired += 1
    rescue StandardError => e
      failed += 1
      Rails.logger.warn(
        "[RepairApprovedNewBusinessCandidates] failed action_candidate_id=#{candidate.id} #{e.class}: #{e.message}"
      )
    end

    say "approved_new_business_candidates checked=#{checked} repaired=#{repaired} skipped=#{skipped} failed=#{failed}"
  end

  def down
    # Non destructive data repair. Do not remove created Business records on rollback.
  end

  private

  def approved_new_business_candidates
    ActionCandidate
      .where(status: "approved")
      .where(
        "department = :department OR action_type IN (:action_types) OR generation_source IN (:sources) OR metadata ->> 'candidate_kind' = :candidate_kind",
        department: "new_business",
        action_types: Aicoo::ActionCandidateBusinessPromoter::NEW_BUSINESS_ACTION_TYPES,
        sources: Aicoo::ActionCandidateBusinessPromoter::NEW_BUSINESS_SOURCES,
        candidate_kind: "new_business"
      )
  end

  def already_promoted?(candidate)
    candidate.metadata.to_h.dig("business_promotion", "promoted") &&
      Business.real_businesses.exists?(id: candidate.business_id)
  end
end
