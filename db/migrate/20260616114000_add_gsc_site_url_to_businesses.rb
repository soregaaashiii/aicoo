class AddGscSiteUrlToBusinesses < ActiveRecord::Migration[8.1]
  def change
    add_column :businesses, :gsc_site_url, :string
  end
end
