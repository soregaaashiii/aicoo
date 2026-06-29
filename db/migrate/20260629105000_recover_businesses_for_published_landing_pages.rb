class RecoverBusinessesForPublishedLandingPages < ActiveRecord::Migration[8.1]
  def up
    AicooLabLandingPage.reset_column_information
    AicooLabExperimentCandidate.reset_column_information
    Business.reset_column_information

    AicooLabLandingPage.publicly_available.where(business_id: nil).find_each do |landing_page|
      landing_page.ensure_business!(source: "published_landing_page_recovery")
    end
  end

  def down
    # Data recovery only. Do not unlink or delete recovered businesses on rollback.
  end
end
