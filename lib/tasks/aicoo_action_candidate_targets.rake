namespace :aicoo do
  desc "Repair ActionCandidate target/planned/reference URL metadata without deleting data."
  task repair_action_candidate_target_urls: :environment do
    apply = ENV["APPLY"].to_s.in?(%w[1 true TRUE])
    checked = 0
    external_target_found = 0
    moved_to_reference = 0
    own_target_reassigned = 0
    planned_url_assigned = 0
    unresolved = 0
    failed = 0
    candidate_ids = []

    ActionCandidate.includes(:business).where.not(business_id: nil).find_each do |candidate|
      checked += 1
      before = candidate.metadata.to_h
      before_refs = reference_urls(before)
      had_external_target = external_target?(candidate.business, before)
      repaired = Aicoo::ActionCandidateTargetSanitizer.call(
        business: candidate.business,
        metadata: before,
        action_type: candidate.action_type
      )

      after_refs = reference_urls(repaired)
      changed = repaired != before
      next unless changed || had_external_target

      candidate_ids << candidate.id
      external_target_found += 1 if had_external_target
      moved_to_reference += 1 if (after_refs - before_refs).any?
      own_target_reassigned += 1 if owner_target_assigned?(candidate.business, before, repaired)
      planned_url_assigned += 1 if before["planned_url"].blank? && repaired["planned_url"].present?
      unresolved += 1 if repaired["target_url"].blank? && repaired["planned_url"].blank?
      candidate.update_columns(metadata: repaired, updated_at: Time.current) if apply && changed
    rescue StandardError => e
      failed += 1
      Rails.logger.warn("[aicoo:repair_action_candidate_target_urls] action_candidate_id=#{candidate&.id} failed: #{e.class}: #{e.message}")
    end

    puts "mode=#{apply ? 'apply' : 'dry_run'}"
    puts "checked=#{checked}"
    puts "external_target_found=#{external_target_found}"
    puts "moved_to_reference=#{moved_to_reference}"
    puts "own_target_reassigned=#{own_target_reassigned}"
    puts "planned_url_assigned=#{planned_url_assigned}"
    puts "unresolved=#{unresolved}"
    puts "failed=#{failed}"
    puts "candidate_ids=#{candidate_ids.uniq.join(',')}"
  end

  def reference_urls(metadata)
    (
      Array(metadata["reference_urls"]) +
      Array(metadata["competitor_urls"]) +
      Array(metadata["external_reference_urls"]) +
      Array(metadata["source_urls"]) +
      Array(metadata["serp_urls"])
    ).compact_blank.uniq
  end

  def external_target?(business, metadata)
    %w[target_url target_url_or_identifier target_identifier page_path].any? do |key|
      value = metadata[key].to_s
      next false unless value.match?(/\Ahttps?:\/\//i)

      Aicoo::BusinessOwnedUrlPolicy.call(business:, url: value).reference_url.present?
    end
  end

  def owner_target_assigned?(business, before, repaired)
    before["target_url"] != repaired["target_url"] &&
      repaired["target_url"].present? &&
      Aicoo::BusinessOwnedUrlPolicy.call(business:, url: repaired["target_url"]).owner_page?
  end
end
