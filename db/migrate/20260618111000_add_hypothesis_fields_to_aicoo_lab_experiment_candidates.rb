class AddHypothesisFieldsToAicooLabExperimentCandidates < ActiveRecord::Migration[8.0]
  def change
    add_column :aicoo_lab_experiment_candidates, :target_user, :string
    add_column :aicoo_lab_experiment_candidates, :problem_statement, :text
    add_column :aicoo_lab_experiment_candidates, :hypothesis, :text
    add_column :aicoo_lab_experiment_candidates, :validation_method, :text
    add_column :aicoo_lab_experiment_candidates, :expected_learning, :text
    add_column :aicoo_lab_experiment_candidates, :rejection_condition, :text
  end
end
