class AddLandingPagePauseState < ActiveRecord::Migration[8.1]
  def change
    add_column :aicoo_lab_landing_pages, :pause_reason, :string
    add_column :aicoo_lab_landing_pages, :pause_comment, :text
    add_column :aicoo_lab_landing_pages, :paused_at, :datetime
    add_column :aicoo_lab_landing_pages, :paused_by, :string
    add_column :aicoo_lab_landing_pages, :resumed_at, :datetime
    add_column :aicoo_lab_landing_pages, :resumed_by, :string

    add_index :aicoo_lab_landing_pages, :pause_reason
    add_index :aicoo_lab_landing_pages, :paused_at

    create_table :aicoo_lab_landing_page_publication_events do |t|
      t.references :aicoo_lab_landing_page, null: false, foreign_key: true
      t.string :event_type, null: false
      t.string :from_status
      t.string :to_status
      t.string :reason
      t.string :operator
      t.text :comment
      t.jsonb :metadata, default: {}, null: false
      t.datetime :occurred_at, null: false

      t.timestamps
    end

    add_index :aicoo_lab_landing_page_publication_events, :event_type
    add_index :aicoo_lab_landing_page_publication_events, :occurred_at
  end
end
