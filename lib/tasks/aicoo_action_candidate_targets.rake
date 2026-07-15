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
    invalid_target = 0
    rejected_irrelevant = 0
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
      repaired = repaired.merge(
        "target_url_repair" => {
          "before_target_url" => before["target_url"],
          "after_target_url" => repaired["target_url"],
          "before_target_url_type" => before["target_url_type"],
          "after_target_url_type" => repaired["target_url_type"],
          "url_classification" => repaired["url_classification"],
          "url_classification_reason" => repaired["url_classification_reason"],
          "processed_at" => Time.current.iso8601
        }
      )
      new_status = repaired_status_for(candidate, repaired)

      after_refs = reference_urls(repaired)
      changed = repaired != before || (new_status.present? && candidate.status != new_status)
      next unless changed || had_external_target

      candidate_ids << candidate.id
      external_target_found += 1 if had_external_target
      moved_to_reference += 1 if (after_refs - before_refs).any?
      own_target_reassigned += 1 if owner_target_assigned?(candidate.business, before, repaired)
      planned_url_assigned += 1 if before["planned_url"].blank? && repaired["planned_url"].present?
      unresolved += 1 if repaired["target_url"].blank? && repaired["planned_url"].blank?
      invalid_target += 1 if repaired["url_classification"].to_s.in?(%w[external_reference invalid])
      rejected_irrelevant += 1 if new_status == "rejected"
      candidate.update_columns({ metadata: repaired, updated_at: Time.current }.merge(new_status ? { status: new_status } : {})) if apply && changed
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
    puts "invalid_target=#{invalid_target}"
    puts "rejected_irrelevant=#{rejected_irrelevant}"
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

  def repaired_status_for(candidate, metadata)
    return if candidate.action_type.to_s.in?(%w[new_article_candidate article_create seo_article]) && metadata["planned_url"].present?

    return "rejected" if metadata["url_classification"].to_s.in?(%w[external_reference invalid])
    return "rejected" if candidate.action_type.to_s.in?(%w[seo_improvement article_update]) && metadata["target_url"].blank?

    nil
  end
end
