class AddBusinessToAicooLabLandingPages < ActiveRecord::Migration[8.1]
  def change
    add_reference :aicoo_lab_landing_pages, :business, foreign_key: true
  end
end
