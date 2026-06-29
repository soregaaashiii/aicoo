class RepairIdeaPipelineBusinessLinks < ActiveRecord::Migration[8.1]
  def up
    say_with_time "Repair Idea Pipeline Business links" do
      repaired = 0

      IdeaPipelineItem.reset_column_information
      AicooLabLandingPage.reset_column_information
      Business.reset_column_information

      IdeaPipelineItem.includes(:aicoo_lab_landing_page).find_each do |item|
        next unless repairable_item?(item)
        next if item.business_id.present? && item.aicoo_lab_landing_page&.business_id.present?

        Aicoo::IdeaPipeline::BusinessLinker.new(item).call
        repaired += 1
      rescue StandardError => error
        Rails.logger.warn(
          "[RepairIdeaPipelineBusinessLinks] failed item_id=#{item.id} " \
          "status=#{item.status} error=#{error.class}: #{error.message}"
        )
      end

      AicooLabLandingPage.publicly_available.where(business_id: nil).find_each do |landing_page|
        landing_page.ensure_business!(source: "published_landing_page_recovery")
        repaired += 1
      rescue StandardError => error
        Rails.logger.warn(
          "[RepairIdeaPipelineBusinessLinks] failed landing_page_id=#{landing_page.id} " \
          "error=#{error.class}: #{error.message}"
        )
      end

      repaired
    end
  end

  def down
    # Data repair only. Do not unlink created Business records automatically.
  end

  private

  def repairable_item?(item)
    item.aicoo_lab_landing_page&.publicly_visible? ||
      item.mvp_decided_at.present? ||
      item.status.in?(%w[published continuing mvp_spec_ready improving])
  end
end
