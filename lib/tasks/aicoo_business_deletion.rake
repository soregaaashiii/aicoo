namespace :aicoo do
  desc "List disposable SERP/generated businesses without deleting them"
  task diagnose_disposable_businesses: :environment do
    scope = Business.real_businesses
                    .where(status: %w[discovered draft exploring])
                    .left_joins(:business_metric_dailies, :revenue_events)
                    .group("businesses.id")
                    .having("COALESCE(SUM(business_metric_dailies.clicks), 0) = 0")
                    .having("COALESCE(SUM(business_metric_dailies.impressions), 0) = 0")
                    .having("COALESCE(SUM(business_metric_dailies.sessions), 0) = 0")
                    .having("COALESCE(SUM(revenue_events.amount), 0) = 0")

    puts "disposable_business_candidates=#{scope.count.size}"
    scope.order(created_at: :desc).find_each do |business|
      puts [
        "id=#{business.id}",
        "name=#{business.name}",
        "status=#{business.status}",
        "source=#{business.source.presence || "-"}",
        "serp_generated=#{business.serp_generated?}",
        "action_candidates=#{business.action_candidates.count}",
        "landing_pages=#{business.aicoo_lab_landing_pages.count}",
        "suggested_reason=#{business.serp_generated? ? "SERP誤生成" : "検証不要"}"
      ].join(" ")
    end
  end

  desc "Soft-archive selected SERP/generated businesses. Requires APPLY=1 and BUSINESS_IDS=1,2"
  task archive_serp_generated_businesses: :environment do
    ids = ENV.fetch("BUSINESS_IDS", "").split(",").filter_map { |id| Integer(id.strip, exception: false) }.uniq
    apply = ENV["APPLY"] == "1"

    if ids.empty?
      puts "BUSINESS_IDS is required. Refusing to archive all businesses."
      exit 1
    end

    businesses = Business.real_businesses.where(id: ids)
    puts "target_count=#{businesses.count} apply=#{apply}"
    businesses.find_each do |business|
      reason = business.serp_generated? ? "SERP誤生成" : "検証不要"
      puts "id=#{business.id} name=#{business.name} reason=#{reason} serp_generated=#{business.serp_generated?}"
      next unless apply

      business.soft_delete!(reason:, actor: "rake", source: "aicoo:archive_serp_generated_businesses")
    end
  end

  desc "Diagnose Business/LP/candidate records created around a mistaken Business delete operation"
  task diagnose_business_delete_side_effects: :environment do
    since_time = ENV["SINCE"].present? ? Time.zone.parse(ENV["SINCE"]) : 30.minutes.ago
    until_time = ENV["UNTIL"].present? ? Time.zone.parse(ENV["UNTIL"]) : Time.current
    range = since_time..until_time

    businesses = Business.where(created_at: range).order(:created_at)
    landing_pages = AicooLabLandingPage.where(created_at: range).order(:created_at)
    candidates = ActionCandidate.where(created_at: range).order(:created_at)

    puts "window=#{since_time.iso8601}..#{until_time.iso8601}"
    puts "businesses_created=#{businesses.count}"
    businesses.find_each do |business|
      puts [
        "business_id=#{business.id}",
        "name=#{business.name}",
        "status=#{business.status}",
        "source=#{business.source.presence || "-"}",
        "created_at=#{business.created_at.iso8601}",
        "serp_generated=#{business.serp_generated?}",
        "source_action_candidate_id=#{business.metadata.to_h["source_action_candidate_id"].presence || business.metadata.to_h.dig("auto_new_business_publication", "action_candidate_id").presence || "-"}"
      ].join(" ")
    end

    puts "landing_pages_created=#{landing_pages.count}"
    landing_pages.find_each do |landing_page|
      puts [
        "lp_id=#{landing_page.id}",
        "business_id=#{landing_page.business_id || "-"}",
        "headline=#{landing_page.headline.to_s.inspect}",
        "public_status=#{landing_page.public_status}",
        "published_slug=#{landing_page.published_slug.presence || "-"}",
        "published_at=#{landing_page.published_at&.iso8601 || "-"}",
        "created_at=#{landing_page.created_at.iso8601}",
        "source_action_candidate_id=-"
      ].join(" ")
    end

    puts "action_candidates_created=#{candidates.count}"
    candidates.find_each do |candidate|
      puts [
        "candidate_id=#{candidate.id}",
        "business_id=#{candidate.business_id || "-"}",
        "title=#{candidate.title.to_s.inspect}",
        "action_type=#{candidate.action_type}",
        "status=#{candidate.status}",
        "generation_source=#{candidate.generation_source}",
        "department=#{candidate.department}",
        "created_at=#{candidate.created_at.iso8601}"
      ].join(" ")
    end
  end

  desc "Dry-run rollback helper for mistaken Business delete side effects. APPLY=1 required to archive selected records"
  task rollback_business_delete_side_effects: :environment do
    business_ids = ENV.fetch("BUSINESS_IDS", "").split(",").filter_map { |id| Integer(id.strip, exception: false) }.uniq
    lp_ids = ENV.fetch("LP_IDS", "").split(",").filter_map { |id| Integer(id.strip, exception: false) }.uniq
    apply = ENV["APPLY"] == "1"

    puts "apply=#{apply}"
    puts "business_ids=#{business_ids.join(",").presence || "-"}"
    puts "lp_ids=#{lp_ids.join(",").presence || "-"}"

    Business.where(id: business_ids).find_each do |business|
      puts "business id=#{business.id} name=#{business.name} deleted=#{business.deleted?}"
      next unless apply
      next if business.deleted?

      business.soft_delete!(
        reason: "誤操作による副作用",
        actor: "rake",
        source: "aicoo:rollback_business_delete_side_effects"
      )
    end

    AicooLabLandingPage.where(id: lp_ids).find_each do |landing_page|
      puts "landing_page id=#{landing_page.id} public_status=#{landing_page.public_status} slug=#{landing_page.published_slug.presence || "-"}"
      next unless apply

      landing_page.update!(
        status: "unpublished",
        public_status: "archived",
        notes: [ landing_page.notes, "business_delete_side_effect rollback at #{Time.current.iso8601}" ].compact_blank.join("\n")
      )
    end
  end
end
