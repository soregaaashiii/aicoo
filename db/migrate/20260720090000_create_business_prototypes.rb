class CreateBusinessPrototypes < ActiveRecord::Migration[8.1]
  def change
    create_table :business_prototypes do |t|
      t.references :business, null: false, foreign_key: true
      t.string :prototype_type, null: false
      t.string :name
      t.text :location, null: false
      t.string :status, null: false, default: "active"
      t.string :analysis_status, null: false, default: "pending"
      t.datetime :analyzed_at
      t.jsonb :analysis, null: false, default: {}
      t.jsonb :metadata, null: false, default: {}

      t.timestamps
    end

    add_index :business_prototypes, %i[business_id prototype_type]
    add_index :business_prototypes, %i[business_id status]
    add_index :business_prototypes, :analysis_status
  end
end
