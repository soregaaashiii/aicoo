namespace :aicoo do
  desc "Repair missing Business links for published Idea Pipeline landing pages"
  task repair_idea_pipeline_business_links: :environment do
    repaired = 0

    IdeaPipelineItem.includes(:aicoo_lab_landing_page).find_each do |item|
      next unless item.business_id.blank?
      next unless item.aicoo_lab_landing_page&.publicly_visible? || item.mvp_decided_at.present?

      Aicoo::IdeaPipeline::BusinessLinker.new(item).call
      repaired += 1
    end

    AicooLabLandingPage.publicly_available.where(business_id: nil).find_each do |landing_page|
      landing_page.ensure_business!(source: "published_landing_page_recovery")
      repaired += 1
    end

    puts "Repaired #{repaired} Idea Pipeline / LP Business links."
  end
end
