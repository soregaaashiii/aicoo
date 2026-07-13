namespace :aicoo do
  desc "Repair ActionCandidate target/planned/reference URL metadata without deleting data."
  task repair_action_candidate_target_urls: :environment do
    apply = ENV["APPLY"].to_s.casecmp("true").zero?
    checked = 0
    target_url_repairs = 0
    duplicate_groups = 0
    duplicate_archived = 0
    failed = 0
    groups = Hash.new { |hash, key| hash[key] = [] }

    ActionCandidate.includes(:business).where.not(business_id: nil).find_each do |candidate|
      checked += 1
      before = candidate.metadata.to_h
      repaired = Aicoo::ActionCandidateTargetSanitizer.call(
        business: candidate.business,
        metadata: before,
        action_type: candidate.action_type
      )

      dedupe_key = Aicoo::ActionCandidateUpserter.dedupe_key_for(
        ActionCandidate.new(
          id: candidate.id,
          business: candidate.business,
          title: candidate.title,
          action_type: candidate.action_type,
          metadata: repaired
        )
      )
      repaired["dedupe_key"] ||= dedupe_key if dedupe_key.present?

      if repaired != before
        target_url_repairs += 1
        candidate.update_columns(metadata: repaired, updated_at: Time.current) if apply
      end

      groups[dedupe_key] << candidate.id if dedupe_key.present? && !candidate.status.in?(ActionCandidate::INACTIVE_STATUSES)
    rescue StandardError => e
      failed += 1
      Rails.logger.warn("[aicoo:repair_action_candidate_target_urls] action_candidate_id=#{candidate&.id} failed: #{e.class}: #{e.message}")
    end

    groups.each_value do |ids|
      next if ids.size < 2

      duplicate_groups += 1
      candidates = ActionCandidate.where(id: ids).order(Arel.sql("final_score DESC NULLS LAST, expected_profit_yen DESC NULLS LAST, updated_at DESC"))
      canonical = candidates.first
      duplicates = candidates.where.not(id: canonical.id)
      duplicate_archived += duplicates.count
      next unless apply

      canonical.update_columns(
        metadata: canonical.metadata.to_h.merge(
          "duplicate_candidate_ids" => Array(canonical.metadata.to_h["duplicate_candidate_ids"]).concat(duplicates.pluck(:id)).uniq,
          "duplicate_repair_applied_at" => Time.current.iso8601
        ),
        updated_at: Time.current
      )
      duplicates.find_each do |duplicate|
        duplicate.update_columns(
          status: "archived",
          metadata: duplicate.metadata.to_h.merge(
            "archived_reason" => "duplicate_action_candidate",
            "duplicate_of_action_candidate_id" => canonical.id,
            "duplicate_repair_applied_at" => Time.current.iso8601
          ),
          updated_at: Time.current
        )
      end
    end

    puts "mode=#{apply ? 'apply' : 'dry_run'}"
    puts "checked=#{checked}"
    puts "target_url_repairs=#{target_url_repairs}"
    puts "duplicate_groups=#{duplicate_groups}"
    puts "duplicate_candidates_to_archive=#{duplicate_archived}"
    puts "failed=#{failed}"
  end
end
