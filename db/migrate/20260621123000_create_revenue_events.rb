class CreateRevenueEvents < ActiveRecord::Migration[8.1]
  def change
    create_table :revenue_events do |t|
      t.references :business, null: false, foreign_key: true
      t.date :occurred_on, null: false
      t.integer :amount, null: false
      t.string :event_type, null: false

      t.timestamps
    end

    add_index :revenue_events, :occurred_on
    add_index :revenue_events, :event_type
  end
end
