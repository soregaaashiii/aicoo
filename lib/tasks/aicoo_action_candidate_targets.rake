namespace :aicoo do
  desc "Repair ActionCandidate target/planned/reference URL metadata without deleting data."
  task repair_action_candidate_target_urls: :environment do
    apply = ENV["APPLY"].to_s.in?(%w[1 true TRUE])
    checked = 0
    skipped_not_target = 0
    skipped_already_repaired = 0
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
      repair_reason = repair_target_reason(candidate, before)
      unless repair_reason
        skipped_not_target += 1
        next
      end
      if already_repaired_target?(candidate, before, repair_reason)
        skipped_already_repaired += 1
        next
      end

      before_refs = reference_urls(before)
      had_external_target = external_target?(candidate.business, before)
      repaired = Aicoo::ActionCandidateTargetSanitizer.call(
        business: candidate.business,
        metadata: before,
        action_type: candidate.action_type
      )
      new_status = repaired_status_for(candidate, repaired, repair_reason)
      rejection_reason = rejection_reason_for(repair_reason, new_status)
      repaired = repaired.merge(
        "repair_reason" => repair_reason,
        "rejection_reason" => rejection_reason,
        "target_url_repair" => {
          "task" => "aicoo:repair_action_candidate_target_urls",
          "before_target_url" => before["target_url"],
          "after_target_url" => repaired["target_url"],
          "before_target_url_type" => before["target_url_type"],
          "after_target_url_type" => repaired["target_url_type"],
          "before_status" => candidate.status,
          "after_status" => new_status || candidate.status,
          "url_classification" => repaired["url_classification"],
          "url_classification_reason" => repaired["url_classification_reason"],
          "repair_reason" => repair_reason,
          "rejection_reason" => rejection_reason,
          "processed_at" => Time.current.iso8601
        }
      )

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
    puts "skipped_not_target=#{skipped_not_target}"
    puts "skipped_already_repaired=#{skipped_already_repaired}"
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

  desc "Rollback ActionCandidate target URL repair rejections caused by the previous over-broad repair."
  task rollback_action_candidate_target_url_repair: :environment do
    apply = ENV["APPLY"].to_s.in?(%w[1 true TRUE])
    fallback_status = ENV["FALLBACK_STATUS"].presence || "pending"
    checked = 0
    restorable = 0
    restored = 0
    skipped = 0
    failed = 0
    candidate_ids = []

    ActionCandidate.where(status: "rejected").find_each do |candidate|
      checked += 1
      metadata = candidate.metadata.to_h
      rollback_status = rollback_status_for(candidate, metadata, fallback_status)
      unless rollback_status
        skipped += 1
        next
      end

      restorable += 1
      candidate_ids << candidate.id
      next unless apply

      restored_metadata = metadata.merge(
        "repair_rollback" => {
          "task" => "aicoo:rollback_action_candidate_target_url_repair",
          "from_status" => candidate.status,
          "to_status" => rollback_status,
          "reason" => rollback_reason(candidate, metadata),
          "processed_at" => Time.current.iso8601
        }
      )
      candidate.update_columns(status: rollback_status, metadata: restored_metadata, updated_at: Time.current)
      restored += 1
    rescue StandardError => e
      failed += 1
      Rails.logger.warn("[aicoo:rollback_action_candidate_target_url_repair] action_candidate_id=#{candidate&.id} failed: #{e.class}: #{e.message}")
    end

    puts "mode=#{apply ? 'apply' : 'dry_run'}"
    puts "checked=#{checked}"
    puts "restorable=#{restorable}"
    puts "restored=#{restored}"
    puts "skipped=#{skipped}"
    puts "failed=#{failed}"
    puts "fallback_status=#{fallback_status}"
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

  def repair_target_reason(candidate, metadata)
    return "external_reference" if metadata["url_classification"].to_s == "external_reference" || metadata["target_url_type"].to_s == "external_reference"
    return "invalid_target" if metadata["url_classification"].to_s == "invalid" || metadata["target_url_type"].to_s == "invalid"
    return "external_reference" if external_target?(candidate.business, metadata)
    return "invalid_target" if invalid_target?(candidate.business, metadata)
    return "nonexistent_existing_page" if existing_page_improvement?(candidate) && proposed_existing_target?(candidate.business, metadata)

    nil
  end

  def already_repaired_target?(candidate, metadata, repair_reason)
    repair = metadata["target_url_repair"].to_h
    return false if repair["after_status"].blank?
    return false if metadata["repair_reason"].blank?
    return false if metadata["rejection_reason"].blank?
    return false unless repair["repair_reason"].to_s == repair_reason.to_s
    return false unless metadata["repair_reason"].to_s == repair_reason.to_s
    return false unless repair["after_status"].to_s == candidate.status.to_s

    expected_rejection_reason = rejection_reason_for(repair_reason, repaired_status_for(candidate, metadata, repair_reason))
    expected_rejection_reason.present? && metadata["rejection_reason"].to_s == expected_rejection_reason
  end

  def invalid_target?(business, metadata)
    target_values(metadata).any? do |value|
      next false unless url_like?(value)

      Aicoo::BusinessOwnedUrlPolicy.call(business:, url: value).invalid?
    end
  end

  def proposed_existing_target?(business, metadata)
    target_values(metadata).any? do |value|
      next false unless url_like?(value)

      Aicoo::BusinessOwnedUrlPolicy.call(business:, url: value).proposed_new?
    end
  end

  def target_values(metadata)
    %w[target_url target_url_or_identifier target_identifier page_path].filter_map { |key| metadata[key].presence }
  end

  def url_like?(value)
    value.to_s.start_with?("/") || value.to_s.match?(/\Ahttps?:\/\//i)
  end

  def existing_page_improvement?(candidate)
    candidate.action_type.to_s.in?(%w[seo_improvement article_update]) ||
      candidate.metadata.to_h["work_type"].to_s == "existing_page_improvement"
  end

  def repaired_status_for(candidate, metadata, repair_reason)
    return if candidate.action_type.to_s.in?(%w[new_article_candidate article_create seo_article]) && metadata["planned_url"].present?

    return "rejected" if repair_reason.in?(%w[external_reference invalid_target nonexistent_existing_page])

    nil
  end

  def rejection_reason_for(repair_reason, new_status)
    return unless new_status == "rejected"

    case repair_reason
    when "external_reference"
      "external_reference_target_url"
    when "invalid_target"
      "invalid_target_url"
    when "nonexistent_existing_page"
      "nonexistent_existing_page_target"
    end
  end

  def rollback_status_for(candidate, metadata, fallback_status)
    previous_status = metadata.dig("target_url_repair", "before_status").presence
    return previous_status if previous_status.present? && previous_status != "rejected"
    return fallback_status if accidental_blank_rejection?(candidate, metadata)

    nil
  end

  def accidental_blank_rejection?(candidate, metadata)
    candidate.action_type.to_s.in?(%w[seo_improvement article_update]) &&
      metadata["target_url"].blank? &&
      metadata["planned_url"].blank? &&
      metadata["url_classification"].blank? &&
      metadata["repair_reason"].blank? &&
      metadata["rejection_reason"].blank?
  end

  def rollback_reason(candidate, metadata)
    return "target_url_repair_before_status" if metadata.dig("target_url_repair", "before_status").present?
    return "previous_repair_blank_target_over_rejection" if accidental_blank_rejection?(candidate, metadata)

    "unknown"
  end
end
