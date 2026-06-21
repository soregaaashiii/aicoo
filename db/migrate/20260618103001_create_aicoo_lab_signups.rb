class CreateAicooLabSignups < ActiveRecord::Migration[8.0]
  def change
    create_table :aicoo_lab_signups do |t|
      t.references :aicoo_lab_landing_page, null: false, foreign_key: true
      t.string :email, null: false
      t.text :note
      t.string :ip_hash
      t.text :user_agent
      t.text :referrer

      t.timestamps
    end

    add_index :aicoo_lab_signups, :email
  end
end
