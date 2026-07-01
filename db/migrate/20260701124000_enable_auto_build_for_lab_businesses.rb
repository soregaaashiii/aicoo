class EnableAutoBuildForLabBusinesses < ActiveRecord::Migration[7.1]
  def up
    Business.reset_column_information
    Business.real_businesses
            .where(created_by_aicoo: true)
            .or(Business.real_businesses.where(source: %w[idea_pipeline aicoo_lab]))
            .update_all(auto_build_enabled: true, updated_at: Time.current)
  end

  def down
    # Keep owner changes intact. Auto Build can be disabled from the Business settings UI.
  end
end
