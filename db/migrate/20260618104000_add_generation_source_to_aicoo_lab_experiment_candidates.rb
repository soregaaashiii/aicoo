class AddGenerationSourceToAicooLabExperimentCandidates < ActiveRecord::Migration[8.0]
  def change
    add_column :aicoo_lab_experiment_candidates, :generation_source, :string, null: false, default: "manual"
    add_index :aicoo_lab_experiment_candidates, :generation_source
  end
end
