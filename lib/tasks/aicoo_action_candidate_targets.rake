namespace :aicoo do
  desc "Repair ActionCandidate target/planned/reference URL metadata without deleting data."
  task repair_action_candidate_target_urls: :environment do
    checked = 0
    updated = 0
    failed = 0

    ActionCandidate.includes(:business).where.not(business_id: nil).find_each do |candidate|
      checked += 1
      before = candidate.metadata.to_h
      repaired = Aicoo::ActionCandidateTargetSanitizer.call(
        business: candidate.business,
        metadata: before,
        action_type: candidate.action_type
      )
      next if repaired == before

      candidate.update_columns(metadata: repaired, updated_at: Time.current)
      updated += 1
    rescue StandardError => e
      failed += 1
      Rails.logger.warn("[aicoo:repair_action_candidate_target_urls] action_candidate_id=#{candidate&.id} failed: #{e.class}: #{e.message}")
    end

    puts "checked=#{checked}"
    puts "updated=#{updated}"
    puts "failed=#{failed}"
  end
end
