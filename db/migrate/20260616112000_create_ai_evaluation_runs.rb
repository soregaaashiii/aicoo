class CreateAiEvaluationRuns < ActiveRecord::Migration[8.1]
  def change
    create_table :ai_evaluation_runs do |t|
      t.references :business, null: false, foreign_key: true
      t.text :input_data
      t.text :prompt
      t.text :raw_response
      t.integer :created_action_count
      t.string :model_name

      t.timestamps
    end
  end
end
