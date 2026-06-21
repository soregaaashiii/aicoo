class CreateAicooLabLandingPageEvents < ActiveRecord::Migration[8.0]
  def change
    create_table :aicoo_lab_landing_page_events do |t|
      t.references :aicoo_lab_landing_page, null: false, foreign_key: true
      t.string :event_type, null: false
      t.datetime :occurred_at, null: false
      t.string :ip_hash
      t.text :user_agent
      t.text :referrer
      t.jsonb :metadata, default: {}, null: false

      t.timestamps
    end

    add_index :aicoo_lab_landing_page_events, :event_type
    add_index :aicoo_lab_landing_page_events, :occurred_at
  end
end
