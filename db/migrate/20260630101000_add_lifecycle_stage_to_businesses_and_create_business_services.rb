class AddLifecycleStageToBusinessesAndCreateBusinessServices < ActiveRecord::Migration[8.0]
  def change
    add_column :businesses, :lifecycle_stage, :string, null: false, default: "idea"
    add_index :businesses, :lifecycle_stage
    execute <<~SQL.squish
      UPDATE businesses
      SET lifecycle_stage = CASE
        WHEN status = 'launched' THEN 'production'
        WHEN status = 'building' THEN 'mvp'
        WHEN status = 'withdrawn' THEN 'archived'
        ELSE 'idea'
      END
    SQL

    create_table :business_services do |t|
      t.references :business, null: false, foreign_key: true
      t.string :name, null: false
      t.string :url
      t.string :repository
      t.string :deploy_target
      t.string :render_service
      t.string :stripe_account
      t.string :domain
      t.string :api_endpoint
      t.string :status, null: false, default: "planning"
      t.jsonb :metadata, null: false, default: {}

      t.timestamps
    end

    add_index :business_services, :status
    add_index :business_services, [ :business_id, :name ], unique: true
  end
end
