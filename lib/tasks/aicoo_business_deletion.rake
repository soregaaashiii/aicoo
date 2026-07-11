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
end
